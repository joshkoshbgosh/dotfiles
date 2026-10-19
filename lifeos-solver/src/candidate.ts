import type {
  CandidateRequest,
  PlanningRequest,
  PlanningResponse,
  SolveResult,
  Task,
} from "./protocol.js";
import { applyScenario } from "./scenario.js";

export function candidateIdentity(request: PlanningRequest) {
  return request.candidate === null ? null : {
    candidateId: request.candidate.candidateId,
    revision: request.candidate.revision,
    capturedInputFingerprint: request.candidate.capturedInputFingerprint,
    normalizedRequestId: request.requestId,
  };
}

export function applyCandidateEdits(request: PlanningRequest): PlanningRequest {
  const candidate = request.candidate;
  if (candidate === null) return request;

  const taskOverrides = candidate.estimateOverrides.flatMap((override) =>
    override.kind === "TASK"
      ? [{ taskId: override.taskId, durationMinutes: override.durationMinutes }]
      : []);
  const projectOverrides = candidate.estimateOverrides.flatMap((override) => {
    if (override.kind !== "PROJECT_CAPACITY") return [];
    const project = request.projects.find((item) => item.id === override.projectId)!;
    return [{
      projectId: override.projectId,
      projectEffortMinutes: project.explicitEffortMinutes + override.durationMinutes,
    }];
  });
  const adjusted = applyScenario(request, {
    id: `candidate:${candidate.candidateId}:${candidate.revision}`,
    reservations: [],
    unlockedCommitmentIds: [],
    estimateChanges: taskOverrides,
    intentionChanges: [],
    projectChanges: projectOverrides,
  });

  const excludedTasks = new Set(candidate.exclusions.flatMap((exclusion) =>
    exclusion.kind === "TASK" ? [exclusion.taskId] : []));
  const excludedProjects = new Set(candidate.exclusions.flatMap((exclusion) =>
    exclusion.kind === "PROJECT_CAPACITY" ? [exclusion.projectId] : []));
  const taskSeeds = new Map(candidate.currentPlanSeeds.flatMap((seed) =>
    seed.kind === "TASK" ? [[seed.taskId, seed.start] as const] : []));
  const capacitySeeds = new Map<string, number[]>();
  for (const seed of candidate.currentPlanSeeds) {
    if (seed.kind !== "PROJECT_CAPACITY") continue;
    const starts = capacitySeeds.get(seed.projectId) ?? [];
    starts.push(seed.start);
    capacitySeeds.set(seed.projectId, starts);
  }
  capacitySeeds.forEach((starts) => starts.sort((left, right) => left - right));

  const tasks = adjusted.tasks.flatMap((task) => {
    if (excludedTasks.has(task.id)
        || (task.workType === "virtual" && excludedProjects.has(task.projectId!))) return [];
    const capacityStarts = task.projectId === null ? undefined : capacitySeeds.get(task.projectId);
    const preferredStart = task.workType === "virtual"
      ? capacityStarts?.[task.virtualWork!.ordinal - 1] ?? task.preferredStart
      : taskSeeds.get(task.id) ?? task.preferredStart;
    return [{ ...task, preferredStart }];
  });
  const taskIds = new Set(tasks.map((task) => task.id));
  return {
    ...adjusted,
    candidate,
    scenario: request.scenario,
    tasks,
    intentions: adjusted.intentions.map((intention) => ({
      ...intention,
      matchedTaskIds: intention.matchedTaskIds.filter((taskId) => taskIds.has(taskId)),
    })),
  };
}

function sourceForTask(task: Task) {
  return task.workType === "virtual" ? task.projectId! : task.id;
}

function confidenceForTask(task: Task) {
  return task.workType === "virtual" ? task.virtualWork!.estimateConfidence : null;
}

function sortedUnique(values: string[]) {
  return [...new Set(values)].sort();
}

function exclusionSource(exclusion: CandidateRequest["exclusions"][number]) {
  return exclusion.kind === "TASK" ? exclusion.taskId : exclusion.projectId;
}

export function decorateCandidateResult(
  originalRequest: PlanningRequest,
  effectiveRequest: PlanningRequest,
  result: SolveResult,
): SolveResult {
  const candidate = originalRequest.candidate;
  if (candidate === null) return result;
  const effectiveTasks = new Map(effectiveRequest.tasks.map((task) => [task.id, task]));
  const exact = new Set(candidate.exactPlacements.map((placement) => placement.taskId));
  const seedStartByTaskId = new Map(candidate.currentPlanSeeds.flatMap((seed) =>
    seed.kind === "TASK" ? [[seed.taskId, seed.start] as const] : []));
  const capacityProjectIds = new Set(candidate.currentPlanSeeds.flatMap((seed) =>
    seed.kind === "PROJECT_CAPACITY" ? [seed.projectId] : []));
  for (const projectId of capacityProjectIds) {
    const seeds = candidate.currentPlanSeeds.filter((seed) =>
      seed.kind === "PROJECT_CAPACITY" && seed.projectId === projectId)
      .sort((left, right) => left.start - right.start || left.end - right.end);
    const virtualTasks = effectiveRequest.tasks.filter((task) => task.workType === "virtual"
      && task.projectId === projectId).sort((left, right) =>
      left.virtualWork!.ordinal - right.virtualWork!.ordinal);
    seeds.forEach((seed, index) => {
      const task = virtualTasks[index];
      if (task !== undefined) seedStartByTaskId.set(task.id, seed.start);
    });
  }
  const placements = result.placements.map((placement) => {
    const task = effectiveTasks.get(placement.taskId)!;
    const sourceId = sourceForTask(task);
    const hasSeed = seedStartByTaskId.has(task.id);
    const seedKept = seedStartByTaskId.get(task.id) === placement.start;
    const rationale = placement.kind === "fixed"
      ? "fixed-commitment" as const
      : exact.has(task.id)
        ? "exact-user-placement" as const
        : seedKept
          ? "current-plan-seed-kept" as const
          : hasSeed
            ? "current-plan-seed-moved" as const
            : "solver-selected" as const;
    return {
      ...placement,
      demandKind: task.workType === "virtual" ? "PROJECT_CAPACITY" as const : "TASK" as const,
      sourceId,
      rationale,
      estimateConfidence: confidenceForTask(task),
    };
  });
  const placedTaskIds = new Set(placements.map((placement) => placement.taskId));
  const exclusions = candidate.exclusions.map((exclusion) => {
    if (exclusion.kind === "TASK") {
      const task = originalRequest.tasks.find((item) => item.id === exclusion.taskId)!;
      const override = candidate.estimateOverrides.find((item) =>
        item.kind === "TASK" && item.taskId === task.id);
      return {
        demandKind: "TASK" as const,
        sourceId: task.id,
        taskId: task.id,
        projectId: task.projectId,
        durationMinutes: override?.durationMinutes ?? task.durationMinutes,
        rationale: "user-excluded" as const,
        deadline: task.deadline,
        estimateConfidence: null,
      };
    }
    const project = originalRequest.projects.find((item) => item.id === exclusion.projectId)!;
    const override = candidate.estimateOverrides.find((item) =>
      item.kind === "PROJECT_CAPACITY" && item.projectId === project.id);
    return {
      demandKind: "PROJECT_CAPACITY" as const,
      sourceId: project.id,
      taskId: null,
      projectId: project.id,
      durationMinutes: override?.durationMinutes ?? project.virtualEffortMinutes,
      rationale: "user-excluded" as const,
      deadline: project.deadline,
      estimateConfidence: project.estimateConfidence,
    };
  });
  const omittedTasks = effectiveRequest.tasks.filter((task) => !placedTaskIds.has(task.id));
  const omittedExplicit = omittedTasks.filter((task) => task.workType === "explicit").map((task) => ({
    demandKind: "TASK" as const,
    sourceId: task.id,
    taskId: task.id,
    projectId: task.projectId,
    durationMinutes: task.durationMinutes,
    rationale: task.durationMinutes === null || task.unresolvedWaiting
      ? "unresolved-input" as const : "solver-omitted" as const,
    deadline: task.deadline,
    estimateConfidence: null,
  }));
  const omittedCapacity = [...new Set(omittedTasks.flatMap((task) =>
    task.workType === "virtual" ? [task.projectId!] : []))].map((projectId) => {
    const project = effectiveRequest.projects.find((item) => item.id === projectId)!;
    const tasks = omittedTasks.filter((task) => task.workType === "virtual"
      && task.projectId === projectId);
    return {
      demandKind: "PROJECT_CAPACITY" as const,
      sourceId: projectId,
      taskId: null,
      projectId,
      durationMinutes: tasks.reduce((total, task) => total + (task.durationMinutes ?? 0), 0),
      rationale: "solver-omitted" as const,
      deadline: project.deadline,
      estimateConfidence: project.estimateConfidence,
    };
  });
  const omissions = [...exclusions, ...omittedExplicit, ...omittedCapacity]
    .sort((left, right) => left.sourceId.localeCompare(right.sourceId));

  const placementByTask = new Map(placements.map((placement) => [placement.taskId, placement]));
  const seedOutcomes = [...seedStartByTaskId].map(([taskId, start]) => {
    const task = effectiveTasks.get(taskId)!;
    const sourceId = sourceForTask(task);
    const placement = placementByTask.get(taskId);
    return { sourceId, outcome: placement === undefined ? "omitted" as const
      : placement.start === start ? "kept" as const : "moved" as const };
  });
  const keptSourceIds = sortedUnique(seedOutcomes.filter((seed) => seed.outcome === "kept")
    .map((seed) => seed.sourceId));
  const movedSourceIds = sortedUnique(seedOutcomes.filter((seed) => seed.outcome === "moved")
    .map((seed) => seed.sourceId));
  const omittedSourceIds = sortedUnique(seedOutcomes.filter((seed) => seed.outcome === "omitted")
    .map((seed) => seed.sourceId));
  const capacityPlacements = placements.filter((placement) =>
    placement.demandKind === "PROJECT_CAPACITY");
  const capacityOmissions = omissions.filter((omission) =>
    omission.demandKind === "PROJECT_CAPACITY");
  const confidences = [...capacityPlacements.map((placement) => placement.estimateConfidence),
    ...capacityOmissions.map((omission) => omission.estimateConfidence)]
    .filter((confidence): confidence is "Low" | "Medium" | "High" => confidence !== null);
  const intentionAtRisk = result.intentions.some((intention) =>
    intention.minimumShortfallMinutes > 0 || intention.maximumExcessMinutes > 0);
  const identity = candidateIdentity(originalRequest)!;
  return {
    ...result,
    placements,
    omissions,
    candidateEvidence: {
      identity,
      exactPlacementTaskIds: [...exact].sort(),
      excludedSourceIds: sortedUnique(candidate.exclusions.map(exclusionSource)),
      estimateOverrideSourceIds: sortedUnique(candidate.estimateOverrides.map((override) =>
        override.kind === "TASK" ? override.taskId : override.projectId)),
      seed: {
        totalCount: seedOutcomes.length,
        keptCount: seedOutcomes.filter((seed) => seed.outcome === "kept").length,
        movedCount: seedOutcomes.filter((seed) => seed.outcome === "moved").length,
        omittedCount: seedOutcomes.filter((seed) => seed.outcome === "omitted").length,
        keptSourceIds,
        movedSourceIds,
        omittedSourceIds,
      },
      deadlineStatus: result.feasibility === "UNKNOWN" ? "UNKNOWN"
        : result.feasibility === "PROVEN INFEASIBLE" ? "CONFLICT" : "SATISFIED",
      safetyStatus: result.safety === null ? "UNKNOWN"
        : result.safety === "SAFE" ? "SATISFIED" : "AT_RISK",
      intentionStatus: result.feasibility !== "PROVEN FEASIBLE" ? "UNKNOWN"
        : intentionAtRisk ? "AT_RISK" : "SATISFIED",
      estimateConfidenceStatus: confidences.length === 0 ? "UNKNOWN"
        : confidences.includes("Low") ? "LOW"
          : confidences.includes("Medium") ? "MEDIUM" : "HIGH",
      capacityStatus: result.feasibility !== "PROVEN FEASIBLE" ? "UNKNOWN"
        : capacityOmissions.length > 0 ? "AT_RISK" : "SATISFIED",
      placedCapacityMinutes: capacityPlacements.reduce((total, placement) =>
        total + placement.end - placement.start, 0),
      omittedCapacityMinutes: capacityOmissions.reduce((total, omission) =>
        total + (omission.durationMinutes ?? 0), 0),
    },
  };
}

export function responseIdentityMatches(
  request: PlanningRequest,
  response: PlanningResponse,
) {
  return response.requestId === request.requestId
    && JSON.stringify(response.candidateIdentity) === JSON.stringify(candidateIdentity(request));
}
