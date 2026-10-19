import { applyCandidateEdits, decorateCandidateResult, responseIdentityMatches } from "./candidate.js";
import type { PlanningRequest, PlanningResponse, SolveResult } from "./protocol.js";
import { applyScenario } from "./scenario.js";

function overlaps(leftStart: number, leftEnd: number, rightStart: number, rightEnd: number) {
  return leftStart < rightEnd && rightStart < leftEnd;
}

function mandatoryTaskIds(request: PlanningRequest): Set<string> {
  const tasks = new Map(request.tasks.map((task) => [task.id, task]));
  const mandatory = new Set(request.tasks
    .filter((task) => task.mandatory || task.deadline !== null || task.fixedStart !== null)
    .map((task) => task.id));
  const pending = [...mandatory];
  while (pending.length > 0) {
    const task = tasks.get(pending.pop()!);
    for (const prerequisiteId of task?.prerequisiteIds ?? []) {
      if (!mandatory.has(prerequisiteId)) {
        mandatory.add(prerequisiteId);
        pending.push(prerequisiteId);
      }
    }
  }
  return mandatory;
}

export function verifyHardConstraints(
  request: PlanningRequest,
  result: SolveResult,
): string[] {
  if (result.feasibility !== "PROVEN FEASIBLE") return [];
  const errors: string[] = [];
  const tasks = new Map(request.tasks.map((task) => [task.id, task]));
  const placements = new Map(result.placements.map((placement) => [placement.taskId, placement]));
  const unlocked = new Set(result.unlockedCommitmentIds);
  const duplicateIds = (values: string[], kind: string) => {
    const seen = new Set<string>();
    for (const value of values) {
      if (seen.has(value)) errors.push(`Duplicate ${kind} placement ${value}.`);
      seen.add(value);
    }
  };
  duplicateIds(result.placements.map((placement) => placement.taskId), "task");
  duplicateIds(result.sleepPlacements.map((placement) => placement.id), "sleep");
  duplicateIds(result.reservePlacements.map((placement) => placement.id), "reserve");
  duplicateIds(result.unlockedCommitmentIds, "unlocked commitment");
  for (const taskId of unlocked) {
    if (tasks.get(taskId)?.fixedStart === null || !tasks.has(taskId)) {
      errors.push(`Unlocked commitment ${taskId} is not a fixed-start task.`);
    }
  }

  for (const taskId of mandatoryTaskIds(request)) {
    if (!placements.has(taskId)) errors.push(`Mandatory task ${taskId} is not placed.`);
  }
  const expectedSleep = [...request.sleep.map((block) => block.id)].sort();
  const actualSleep = [...result.sleepPlacements.map((block) => block.id)].sort();
  if (expectedSleep.join("\0") !== actualSleep.join("\0")) {
    errors.push("Sleep placements do not exactly match requested sleep blocks.");
  }
  const expectedReserve = result.safety === "SAFE"
    ? [...request.reserve.map((block) => block.id)].sort()
    : [];
  const actualReserve = [...result.reservePlacements.map((block) => block.id)].sort();
  if (expectedReserve.join("\0") !== actualReserve.join("\0")) {
    errors.push("Reserve placements do not exactly match the applicable reserve blocks.");
  }

  for (const placement of result.placements) {
    const task = tasks.get(placement.taskId);
    if (!task) {
      errors.push(`Unknown placed task ${placement.taskId}.`);
      continue;
    }
    if (task.durationMinutes === null || placement.end - placement.start !== task.durationMinutes) {
      errors.push(`${task.id} has the wrong placed duration.`);
    }
    if (placement.projectId !== task.projectId) {
      errors.push(`${task.id} has the wrong project ownership.`);
    }
    const expectedDemandKind = task.workType === "virtual" ? "PROJECT_CAPACITY" : "TASK";
    const expectedSourceId = task.workType === "virtual" ? task.projectId : task.id;
    const expectedConfidence = task.workType === "virtual"
      ? task.virtualWork!.estimateConfidence : null;
    if (placement.demandKind !== expectedDemandKind || placement.sourceId !== expectedSourceId) {
      errors.push(`${task.id} has the wrong candidate source attribution.`);
    }
    if (placement.estimateConfidence !== expectedConfidence) {
      errors.push(`${task.id} has the wrong estimate-confidence attribution.`);
    }
    const expectedKind = task.fixedStart !== null && !unlocked.has(task.id)
      ? "fixed" : "proposed";
    if (placement.kind !== expectedKind) {
      errors.push(`${task.id} has placement kind ${placement.kind}; expected ${expectedKind}.`);
    }
    if (task.unresolvedWaiting && !mandatoryTaskIds(request).has(task.id)) {
      errors.push(`Optional unresolved WAITING task ${task.id} was selected.`);
    }
    if ((task.fixedStart === null || unlocked.has(task.id))
        && (!isAligned(placement.start, request.schedulingQuantumMinutes)
          || !isAligned(placement.end, request.schedulingQuantumMinutes))) {
      errors.push(`${task.id} is not aligned to the scheduling grid.`);
    }
    if (placement.start < request.horizon.start || placement.end > request.horizon.end) {
      errors.push(`${task.id} is outside the planning horizon.`);
    }
    if (task.releaseTime !== null && placement.start < task.releaseTime) {
      errors.push(`${task.id} starts before its release time.`);
    }
    const available = request.availability.some((window) =>
      (window.modes === undefined || window.modes.includes(task.workMode))
      && placement.start >= window.start && placement.end <= window.end,
    );
    if (!available) errors.push(`${task.id} is outside compatible availability.`);
    for (const block of request.busy) {
      if (overlaps(placement.start, placement.end, block.start, block.end)) {
        errors.push(`${task.id} overlaps busy block ${block.id}.`);
      }
    }
    if (task.fixedStart !== null && !unlocked.has(task.id)
        && placement.start !== task.fixedStart) {
      errors.push(`${task.id} moved from its fixed start.`);
    }
    const exactStart = request.candidate?.exactPlacements.find((candidate) =>
      candidate.taskId === task.id)?.start;
    if (exactStart !== undefined && placement.start !== exactStart) {
      errors.push(`${task.id} moved from its exact candidate placement.`);
    }
    if (task.deadline !== null) {
      const project = task.projectId === null
        ? undefined
        : request.projects.find((candidate) => candidate.id === task.projectId);
      const buffer = result.safety === "SAFE"
        ? (project?.safetyBufferMinutes ?? request.defaultSafetyBufferMinutes)
        : 0;
      if (placement.end > task.deadline - buffer) {
        errors.push(`${task.id} misses its effective deadline or safety buffer.`);
      }
    }
    for (const prerequisiteId of task.prerequisiteIds) {
      const prerequisite = placements.get(prerequisiteId);
      if (!prerequisite || prerequisite.end > placement.start) {
        errors.push(`${task.id} starts before prerequisite ${prerequisiteId} finishes.`);
      }
    }
  }

  const expectedMarginTaskIds = result.placements.filter((placement) =>
    tasks.get(placement.taskId)?.deadline !== null).map((placement) => placement.taskId).sort();
  const actualMarginTaskIds = result.deadlineMargins.map((margin) => margin.taskId).sort();
  if (expectedMarginTaskIds.join("\0") !== actualMarginTaskIds.join("\0")) {
    errors.push("Deadline margins do not exactly match placed deadline work.");
  }
  for (const margin of result.deadlineMargins) {
    const task = tasks.get(margin.taskId);
    const placement = placements.get(margin.taskId);
    const project = task?.projectId === null || task?.projectId === undefined
      ? undefined : request.projects.find((candidate) => candidate.id === task.projectId);
    const safetyBufferMinutes = project?.safetyBufferMinutes
      ?? request.defaultSafetyBufferMinutes;
    if (!task || !placement || task.deadline === null || margin.projectId !== task.projectId
        || margin.deadline !== task.deadline || margin.completionTime !== placement.end
        || margin.hardDeadlineMarginMinutes !== task.deadline - placement.end
        || margin.safetyBufferMinutes !== safetyBufferMinutes
        || margin.safetyMarginMinutes !== task.deadline - safetyBufferMinutes - placement.end) {
      errors.push(`Returned deadline margin for ${margin.taskId} is inconsistent.`);
    }
  }

  for (let index = 0; index < result.placements.length; index += 1) {
    const left = result.placements[index]!;
    for (let other = index + 1; other < result.placements.length; other += 1) {
      const right = result.placements[other]!;
      if (overlaps(left.start, left.end, right.start, right.end)) {
        errors.push(`${left.taskId} overlaps ${right.taskId}.`);
      }
    }
  }

  const protectedBlocks = [
    ...result.sleepPlacements.map((block) => ({ ...block, kind: "sleep" })),
    ...result.reservePlacements.map((block) => ({ ...block, kind: "reserve" })),
  ];
  for (const block of protectedBlocks) {
    if (!isAligned(block.start, request.schedulingQuantumMinutes)
        || !isAligned(block.end, request.schedulingQuantumMinutes)) {
      errors.push(`${block.kind} ${block.id} is not aligned to the scheduling grid.`);
    }
    if (result.placements.some((placement) =>
      overlaps(block.start, block.end, placement.start, placement.end))) {
      errors.push(`${block.kind} ${block.id} overlaps placed work.`);
    }
    if (request.busy.some((busy) => overlaps(block.start, block.end, busy.start, busy.end))) {
      errors.push(`${block.kind} ${block.id} overlaps busy time.`);
    }
    if (block.kind === "reserve") {
      const source = request.reserve.find((candidate) => candidate.id === block.id);
      if (!source || !placementFits(block.start, block.end,
                                    source.envelopeStart, source.envelopeEnd)
          || block.end - block.start !== source.minimumMinutes) {
        errors.push(`reserve ${block.id} violates its envelope or minimum.`);
      }
      const usable = request.availability.some((window) =>
        placementFits(block.start, block.end, window.start, window.end)
        && (source?.modes === undefined
            || source.modes.some((mode) => window.modes?.includes(mode))));
      if (!usable) errors.push(`reserve ${block.id} is outside usable availability.`);
    } else {
      const source = request.sleep.find((candidate) => candidate.id === block.id);
      if (!source || !placementFits(block.start, block.end,
                                    source.envelopeStart, source.envelopeEnd)
          || block.end - block.start !== source.minimumMinutes) {
        errors.push(`sleep ${block.id} violates its envelope or minimum.`);
      }
    }
  }

  for (let index = 0; index < protectedBlocks.length; index += 1) {
    for (let other = index + 1; other < protectedBlocks.length; other += 1) {
      const left = protectedBlocks[index]!;
      const right = protectedBlocks[other]!;
      if (overlaps(left.start, left.end, right.start, right.end)) {
        errors.push(`${left.kind} ${left.id} overlaps ${right.kind} ${right.id}.`);
      }
    }
  }

  return [...new Set(errors)].sort();
}

export function verifyPlanningResponse(
  request: PlanningRequest,
  response: PlanningResponse,
): string[] {
  const errors: string[] = [];
  if (!responseIdentityMatches(request, response)) {
    errors.push("Response identity does not exactly match the normalized candidate request.");
  }
  if (response.status !== "ok") return errors;
  const effectiveRequest = applyCandidateEdits(request);
  if (response.baseline === null) {
    errors.push("Successful response is missing its baseline result.");
  } else {
    errors.push(...verifyHardConstraints(effectiveRequest, response.baseline)
      .map((error) => `Baseline: ${error}`));
    errors.push(...verifyCandidateEvidence(request, effectiveRequest, response.baseline, "Baseline"));
  }
  if (effectiveRequest.scenario === null) {
    if (response.scenario !== null) errors.push("Response contains an unrequested scenario result.");
  } else if (response.scenario === null) {
    errors.push("Response is missing its requested scenario result.");
  } else {
    const scenarioRequest = applyScenario(effectiveRequest, effectiveRequest.scenario);
    errors.push(...verifyHardConstraints(scenarioRequest, response.scenario)
      .map((error) => `Scenario: ${error}`));
    errors.push(...verifyCandidateEvidence(request, scenarioRequest, response.scenario, "Scenario"));
  }
  return [...new Set(errors)].sort();
}

function verifyCandidateEvidence(
  originalRequest: PlanningRequest,
  effectiveRequest: PlanningRequest,
  result: SolveResult,
  label: string,
) {
  if (originalRequest.candidate === null) {
    return result.candidateEvidence === null && result.omissions.length === 0
      ? [] : [`${label}: non-candidate result contains candidate evidence.`];
  }
  const expected = decorateCandidateResult(originalRequest, effectiveRequest, result);
  const errors: string[] = [];
  if (JSON.stringify(result.placements) !== JSON.stringify(expected.placements)) {
    errors.push(`${label}: candidate placement attribution or rationale is inconsistent.`);
  }
  if (JSON.stringify(result.omissions) !== JSON.stringify(expected.omissions)) {
    errors.push(`${label}: candidate omission attribution or rationale is inconsistent.`);
  }
  if (JSON.stringify(result.candidateEvidence) !== JSON.stringify(expected.candidateEvidence)) {
    errors.push(`${label}: candidate planning evidence is inconsistent.`);
  }
  return errors;
}

function placementFits(start: number, end: number, windowStart: number, windowEnd: number) {
  return start >= windowStart && end <= windowEnd;
}

function isAligned(value: number, quantum: number) {
  return value % quantum === 0;
}
