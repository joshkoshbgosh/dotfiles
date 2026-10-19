import { init, killThreads } from "z3-solver";

import {
  SOLVER_VERSION,
  type NegotiationQuery,
  type PlanningRequest,
  type PlanningResponse,
  type SolveResult,
  type Task,
  responseEnvelope,
} from "./protocol.js";
import {
  applyCandidateEdits,
  candidateIdentity,
  decorateCandidateResult,
} from "./candidate.js";
import { applyScenario } from "./scenario.js";
import { verifyHardConstraints } from "./verify.js";

const PRIORITY_SCORE = { A: 40, B: 30, C: 20, D: 10 } as const;
const IMPACT_SCORE = { High: 3, Medium: 2, Low: 1 } as const;

interface ConstraintInfo {
  expr: any;
  constraintId: string;
  sourceId: string;
  kind: string;
  message: string;
  taskIds: string[];
  projectIds: string[];
  shared: boolean;
}

interface TaskVars {
  task: Task;
  start: any;
  end: any;
  selected: any;
}

interface FlexibleBlockVars {
  id: string;
  start: any;
  end: any;
}

interface EncodedModel {
  context: any;
  constraints: ConstraintInfo[];
  tasks: Map<string, TaskVars>;
  sleep: FlexibleBlockVars[];
  reserve: FlexibleBlockVars[];
  intentionAllocations: Map<string, any>;
}

type Conflict = SolveResult["conflicts"][number];

function relaxationForKind(kind: string): Conflict["relaxation"] {
  switch (kind) {
    case "fixed-start":
      return {
        type: "unlock-commitment",
        text: "Unlock this fixed commitment so it can be rescheduled.",
      };
    case "availability":
      return {
        type: "add-compatible-availability",
        text: "Add an availability window compatible with this task's work mode.",
      };
    case "unknown-duration":
      return {
        type: "provide-duration-estimate",
        text: "Provide a remaining-duration estimate before scheduling this task.",
      };
    case "unresolved-waiting":
      return {
        type: "model-release-condition",
        text: "Model when the waiting task can be released, or remove it from required work.",
      };
    case "deadline-buffer":
    case "reserve":
      return {
        type: "adjust-safety-policy",
        text: "Adjust the safety buffer or reserve policy; this does not weaken the hard deadline.",
      };
    case "release-time":
      return {
        type: "move-after-release",
        text: "Move the task to or after its release time.",
      };
    case "preflight":
      return {
        type: "resolve-input-assumption",
        text: "Resolve the incomplete planning input before relying on solver assurance.",
      };
    default:
      return undefined;
  }
}

function mappedConflict(info: Omit<ConstraintInfo, "expr">): Conflict {
  const relaxation = relaxationForKind(info.kind);
  return relaxation === undefined ? info : { ...info, relaxation };
}

function unknownResult(assumptions: string[], unlocked: string[] = []): SolveResult {
  return {
    feasibility: "UNKNOWN",
    safety: null,
    resilience: null,
    placements: [],
    reservePlacements: [],
    sleepPlacements: [],
    intentions: [],
    deadlineMargins: [],
    omissions: [],
    candidateEvidence: null,
    conflicts: [],
    assumptions,
    unlockedCommitmentIds: [...unlocked].sort(),
    stressResults: [],
  };
}

function preflightConflicts(request: PlanningRequest, issues: string[]): Conflict[] {
  return issues.map((message, index) => {
    const unknownDuration = /^Mandatory task (.+) has unknown remaining duration\.$/.exec(message);
    const unresolvedWaiting = /^Mandatory WAITING task (.+) has no modeled release condition\.$/
      .exec(message);
    const taskId = unknownDuration?.[1] ?? unresolvedWaiting?.[1];
    const task = taskId === undefined
      ? undefined
      : request.tasks.find((candidate) => candidate.id === taskId);
    return mappedConflict({
      constraintId: `preflight:${index}`,
      sourceId: task?.evidence.sourceId ?? request.requestId,
      kind: unknownDuration ? "unknown-duration"
        : unresolvedWaiting ? "unresolved-waiting" : "preflight",
      message,
      taskIds: task === undefined ? [] : [task.id],
      projectIds: task?.projectId === null || task?.projectId === undefined
        ? [] : [task.projectId],
      shared: task === undefined,
    });
  });
}

function mandatoryTaskIds(request: PlanningRequest): Set<string> {
  const byId = new Map(request.tasks.map((task) => [task.id, task]));
  const mandatory = new Set(
    request.tasks
      .filter((task) => task.mandatory || task.deadline !== null || task.fixedStart !== null)
      .map((task) => task.id),
  );
  const pending = [...mandatory];
  while (pending.length > 0) {
    const task = byId.get(pending.pop()!);
    for (const prerequisiteId of task?.prerequisiteIds ?? []) {
      if (!mandatory.has(prerequisiteId)) {
        mandatory.add(prerequisiteId);
        pending.push(prerequisiteId);
      }
    }
  }
  return mandatory;
}

function preflight(request: PlanningRequest): string[] {
  const byId = new Set(request.tasks.map((task) => task.id));
  const mandatory = mandatoryTaskIds(request);
  const issues: string[] = [...request.hardIssues];
  for (const id of mandatory) {
    const task = request.tasks.find((candidate) => candidate.id === id);
    if (!task) {
      issues.push(`Mandatory prerequisite ${id} is absent from the normalized model.`);
    } else if (task.durationMinutes === null) {
      issues.push(`Mandatory task ${id} has unknown remaining duration.`);
    } else if (task.unresolvedWaiting) {
      issues.push(`Mandatory WAITING task ${id} has no modeled release condition.`);
    }
  }
  for (const task of request.tasks) {
    for (const prerequisiteId of task.prerequisiteIds) {
      if (!byId.has(prerequisiteId)) {
        issues.push(`Task ${task.id} references missing prerequisite ${prerequisiteId}.`);
      }
    }
  }
  const assuranceEnd = Math.max(
    request.horizon.end,
    ...request.tasks.flatMap((task) => [
      task.deadline ?? request.horizon.start,
      task.fixedStart !== null && task.durationMinutes !== null
        ? task.fixedStart + task.durationMinutes
        : request.horizon.start,
    ]),
  );
  if (request.horizon.end < assuranceEnd) {
    issues.push("The supplied horizon does not reach every known deadline or fixed commitment.");
  }
  if (request.calendarCoverageEnd < assuranceEnd) {
    issues.push("Calendar coverage ends before the assurance horizon.");
  }
  if (request.availabilityCoverageEnd < assuranceEnd) {
    issues.push("Availability coverage ends before the assurance horizon.");
  }
  return [...new Set(issues)].sort();
}

function compatibleAvailability(request: PlanningRequest, task: Task) {
  return request.availability.filter((window) =>
    window.kind === "availability"
      && (window.modes === undefined || window.modes.includes(task.workMode)),
  );
}

function nonOverlap(leftStart: any, leftEnd: any, rightStart: any, rightEnd: any) {
  return leftEnd.le(rightStart).or(rightEnd.le(leftStart));
}

function encode(
  request: PlanningRequest,
  context: any,
  includeSafety: boolean,
  unlocked: Set<string>,
): EncodedModel {
  const { Int, Bool, Or, Implies, If, Sum } = context;
  const mandatory = mandatoryTaskIds(request);
  const exactPlacements = new Map(
    (request.candidate?.exactPlacements ?? []).map((placement) =>
      [placement.taskId, placement.start]),
  );
  const constraints: ConstraintInfo[] = [];
  const tasks = new Map<string, TaskVars>();
  const add = (
    expr: any,
    constraintId: string,
    sourceId: string,
    kind: string,
    message: string,
    ownerTaskIds?: string[],
    includesSharedOwnership?: boolean,
  ) => {
    const taskIds = [...new Set(ownerTaskIds ?? request.tasks
      .filter((task) => task.evidence.sourceId === sourceId).map((task) => task.id))].sort();
    const projectIds = [...new Set([
      ...taskIds.flatMap((taskId) => {
        const projectId = request.tasks.find((task) => task.id === taskId)?.projectId;
        return projectId === null || projectId === undefined ? [] : [projectId];
      }),
      ...request.projects.filter((project) => project.evidence.sourceId === sourceId)
        .map((project) => project.id),
    ])].sort();
    constraints.push({ expr, constraintId, sourceId, kind, message, taskIds, projectIds,
      shared: includesSharedOwnership ?? (taskIds.length === 0 && projectIds.length === 0) });
  };

  for (const task of [...request.tasks].sort((a, b) => a.id.localeCompare(b.id))) {
    const start = Int.const(`task_${task.id}_start`);
    const end = Int.const(`task_${task.id}_end`);
    const selected = Bool.const(`task_${task.id}_selected`);
    const duration = task.durationMinutes ?? request.schedulingQuantumMinutes;
    tasks.set(task.id, { task, start, end, selected });
    add(
      end.eq(start.add(duration)),
      `task:${task.id}:duration`, task.evidence.sourceId, "duration",
      `${task.id} requires ${duration} contiguous minutes.`,
    );
    add(
      Implies(selected, start.ge(request.horizon.start).and(end.le(request.horizon.end))),
      `task:${task.id}:horizon`, task.evidence.sourceId, "horizon",
      `${task.id} must fit inside the planning horizon.`,
    );
    if (task.fixedStart === null || unlocked.has(task.id)) {
      add(
        Implies(selected, start.mod(request.schedulingQuantumMinutes).eq(0)
          .and(end.mod(request.schedulingQuantumMinutes).eq(0))),
        `task:${task.id}:quantum`, task.evidence.sourceId, "scheduling-quantum",
        `${task.id} must align to the scheduling grid.`,
      );
    }
    if (task.releaseTime !== null) {
      add(
        Implies(selected, start.ge(task.releaseTime)),
        `task:${task.id}:release`, task.evidence.sourceId, "release-time",
        `${task.id} cannot start before its release time ${task.releaseTime}.`,
      );
    }
    if (mandatory.has(task.id)) {
      add(selected, `task:${task.id}:mandatory`, task.evidence.sourceId, "mandatory",
          `${task.id} is mandatory work.`);
    } else if (task.durationMinutes === null || task.unresolvedWaiting) {
      add(selected.not(), `task:${task.id}:unknown-optional`, task.evidence.sourceId,
          task.unresolvedWaiting ? "unresolved-waiting" : "unknown-duration",
          `${task.id} cannot be selected while its scheduling inputs are unresolved.`);
    }

    const windows = compatibleAvailability(request, task);
    const availabilityExpr = windows.length > 0
      ? Or(...windows.map((window) => start.ge(window.start).and(end.le(window.end))))
      : Bool.val(false);
    add(
      Implies(selected, availabilityExpr),
      `task:${task.id}:availability`, task.evidence.sourceId, "availability",
      `${task.id} needs a compatible ${task.workMode} availability window.`,
      [task.id], true,
    );

    for (const block of request.busy) {
      add(
        Implies(selected, nonOverlap(start, end, Int.val(block.start), Int.val(block.end))),
        `task:${task.id}:block:${block.id}`,
        block.evidence?.sourceId ?? block.id,
        block.kind,
        `${task.id} conflicts with ${block.kind} block ${block.id}.`,
        [task.id], true,
      );
    }

    if (task.fixedStart !== null && !unlocked.has(task.id)) {
      add(
        Implies(selected, start.eq(task.fixedStart)),
        `task:${task.id}:fixed`, task.evidence.sourceId, "fixed-start",
        `${task.id} is fixed at ${task.fixedStart}.`,
      );
    }
    const exactStart = exactPlacements.get(task.id);
    if (exactStart !== undefined) {
      add(
        selected.and(start.eq(exactStart)),
        `task:${task.id}:exact-candidate-placement`, task.evidence.sourceId,
        "exact-placement", `${task.id} must use the exact candidate start ${exactStart}.`,
      );
    }
    if (task.deadline !== null) {
      const project = task.projectId === null
        ? undefined
        : request.projects.find((candidate) => candidate.id === task.projectId);
      const buffer = includeSafety
        ? (project?.safetyBufferMinutes ?? request.defaultSafetyBufferMinutes)
        : 0;
      add(
        Implies(selected, end.le(task.deadline - buffer)),
        `task:${task.id}:${includeSafety ? "safe-" : ""}deadline`,
        task.evidence.sourceId,
        includeSafety ? "deadline-buffer" : "deadline",
        `${task.id} must finish by ${task.deadline - buffer}.`,
      );
    }
  }

  const taskList = [...tasks.values()];
  for (let index = 0; index < taskList.length; index += 1) {
    const left = taskList[index]!;
    for (let other = index + 1; other < taskList.length; other += 1) {
      const right = taskList[other]!;
      add(
        Implies(left.selected.and(right.selected),
                nonOverlap(left.start, left.end, right.start, right.end)),
        `tasks:${left.task.id}:${right.task.id}:no-overlap`,
        left.task.evidence.sourceId,
        "task-overlap",
        `${left.task.id} and ${right.task.id} may not overlap.`,
        [left.task.id, right.task.id],
      );
    }
  }

  for (const current of taskList) {
    for (const prerequisiteId of current.task.prerequisiteIds) {
      const prerequisite = tasks.get(prerequisiteId);
      if (!prerequisite) continue;
      add(
        Implies(current.selected,
                prerequisite.selected.and(prerequisite.end.le(current.start))),
        `dependency:${current.task.id}:${prerequisiteId}`,
        current.task.evidence.sourceId,
        "dependency",
        `${prerequisiteId} must finish before ${current.task.id} starts.`,
        [current.task.id, prerequisiteId],
      );
    }
  }

  const sleep = request.sleep.map((block) => {
    const start = Int.const(`sleep_${block.id}_start`);
    const end = start.add(block.minimumMinutes);
    add(start.ge(block.envelopeStart).and(end.le(block.envelopeEnd)),
        `sleep:${block.id}:envelope`, block.evidence.sourceId, "sleep",
         `Sleep ${block.id} must fit its envelope.`);
    add(start.mod(request.schedulingQuantumMinutes).eq(0)
          .and(end.mod(request.schedulingQuantumMinutes).eq(0)),
        `sleep:${block.id}:quantum`, block.evidence.sourceId, "scheduling-quantum",
        `Sleep ${block.id} must align to the scheduling grid.`);
    for (const busy of request.busy) {
      add(nonOverlap(start, end, Int.val(busy.start), Int.val(busy.end)),
          `sleep:${block.id}:block:${busy.id}`, busy.evidence?.sourceId ?? busy.id,
          "sleep", `Sleep ${block.id} conflicts with ${busy.id}.`);
    }
    for (const task of taskList) {
      add(Implies(task.selected, nonOverlap(start, end, task.start, task.end)),
          `sleep:${block.id}:task:${task.task.id}`, block.evidence.sourceId,
          "sleep", `Sleep ${block.id} may not overlap ${task.task.id}.`,
          [task.task.id], true);
    }
    return { id: block.id, start, end };
  });

  for (let index = 0; index < sleep.length; index += 1) {
    for (let other = index + 1; other < sleep.length; other += 1) {
      const left = sleep[index]!;
      const right = sleep[other]!;
      add(nonOverlap(left.start, left.end, right.start, right.end),
          `sleep:${left.id}:${right.id}:no-overlap`, left.id, "sleep",
          `Sleep intervals ${left.id} and ${right.id} may not overlap.`);
    }
  }

  const reserve = includeSafety ? request.reserve.map((block) => {
    const start = Int.const(`reserve_${block.id}_start`);
    const end = start.add(block.minimumMinutes);
    add(start.ge(block.envelopeStart).and(end.le(block.envelopeEnd)),
        `reserve:${block.id}:envelope`, block.evidence.sourceId, "reserve",
        `Reserve ${block.id} must fit its envelope.`);
    add(start.mod(request.schedulingQuantumMinutes).eq(0)
          .and(end.mod(request.schedulingQuantumMinutes).eq(0)),
        `reserve:${block.id}:quantum`, block.evidence.sourceId, "scheduling-quantum",
        `Reserve ${block.id} must align to the scheduling grid.`);
    const compatibleWindows = request.availability.filter((window) =>
      block.modes === undefined || block.modes.some((mode) => window.modes?.includes(mode)));
    add(
      compatibleWindows.length > 0
        ? Or(...compatibleWindows.map((window) =>
            start.ge(window.start).and(end.le(window.end))))
        : Bool.val(false),
      `reserve:${block.id}:availability`, block.evidence.sourceId, "reserve",
      `Reserve ${block.id} must protect usable availability.`,
    );
    for (const busy of request.busy) {
      add(nonOverlap(start, end, Int.val(busy.start), Int.val(busy.end)),
          `reserve:${block.id}:block:${busy.id}`, busy.evidence?.sourceId ?? busy.id,
          "reserve", `Reserve ${block.id} conflicts with ${busy.id}.`);
    }
    for (const task of taskList) {
      add(Implies(task.selected, nonOverlap(start, end, task.start, task.end)),
          `reserve:${block.id}:task:${task.task.id}`, block.evidence.sourceId,
          "reserve", `Reserve ${block.id} may not overlap ${task.task.id}.`,
          [task.task.id], true);
    }
    for (const sleeping of sleep) {
      add(nonOverlap(start, end, sleeping.start, sleeping.end),
          `reserve:${block.id}:sleep:${sleeping.id}`, block.evidence.sourceId,
          "reserve", `Reserve ${block.id} may not overlap sleep ${sleeping.id}.`);
    }
    return { id: block.id, start, end };
  }) : [];

  for (let index = 0; index < reserve.length; index += 1) {
    for (let other = index + 1; other < reserve.length; other += 1) {
      const left = reserve[index]!;
      const right = reserve[other]!;
      add(nonOverlap(left.start, left.end, right.start, right.end),
          `reserve:${left.id}:${right.id}:no-overlap`, left.id, "reserve",
          `Reserve blocks ${left.id} and ${right.id} may not overlap.`);
    }
  }

  const intentionAllocations = new Map<string, any>();
  for (const intention of request.intentions) {
    const matched = intention.matchedTaskIds
      .map((taskId) => tasks.get(taskId))
      .filter((task): task is TaskVars => task !== undefined);
    intentionAllocations.set(
      intention.id,
      Sum(Int.val(intention.actualMinutes),
          ...matched.map((item) => If(
              item.selected.and(item.start.ge(intention.windowStart))
                .and(item.end.le(intention.windowEnd)),
              Int.val(item.task.durationMinutes ?? 0), Int.val(0)))),
    );
  }

  return { context, constraints, tasks, sleep, reserve, intentionAllocations };
}

function intFromModel(model: any, expression: any): number {
  return Number.parseInt(model.eval(expression, true).toString(), 10);
}

function resultFromModel(
  request: PlanningRequest,
  encoded: EncodedModel,
  model: any,
  safety: "SAFE" | "TIGHT",
  unlocked: Set<string>,
  assumptions: string[] = [],
): SolveResult {
  const placements = [...encoded.tasks.values()]
    .filter((item) => model.eval(item.selected, true).toString() === "true")
    .map((item) => ({
      taskId: item.task.id,
      projectId: item.task.projectId,
      demandKind: item.task.workType === "virtual" ? "PROJECT_CAPACITY" as const : "TASK" as const,
      sourceId: item.task.workType === "virtual" ? item.task.projectId! : item.task.id,
      start: intFromModel(model, item.start),
      end: intFromModel(model, item.end),
      kind: item.task.fixedStart !== null && !unlocked.has(item.task.id)
        ? "fixed" as const
        : "proposed" as const,
      rationale: item.task.fixedStart !== null && !unlocked.has(item.task.id)
        ? "fixed-commitment" as const : "solver-selected" as const,
      estimateConfidence: item.task.workType === "virtual"
        ? item.task.virtualWork!.estimateConfidence : null,
    }))
    .sort((a, b) => a.start - b.start || a.taskId.localeCompare(b.taskId));
  const intentionResults = request.intentions.map((intention) => {
    const allocated = intFromModel(model, encoded.intentionAllocations.get(intention.id));
    return {
      id: intention.id,
      allocatedMinutes: allocated,
      minimumShortfallMinutes: intention.minimumMinutes === null
        ? 0 : Math.max(0, intention.minimumMinutes - allocated),
      targetDeviationMinutes: intention.targetMinutes === null
        ? 0 : Math.abs(intention.targetMinutes - allocated),
      maximumExcessMinutes: intention.maximumMinutes === null
        ? 0 : Math.max(0, allocated - intention.maximumMinutes),
    };
  });
  const deadlineMargins = placements.flatMap((placement) => {
    const task = request.tasks.find((candidate) => candidate.id === placement.taskId);
    if (!task || task.deadline === null) return [];
    const project = task.projectId === null
      ? undefined
      : request.projects.find((candidate) => candidate.id === task.projectId);
    const safetyBufferMinutes = project?.safetyBufferMinutes
      ?? request.defaultSafetyBufferMinutes;
    return [{
      taskId: task.id,
      projectId: task.projectId,
      deadline: task.deadline,
      completionTime: placement.end,
      hardDeadlineMarginMinutes: task.deadline - placement.end,
      safetyBufferMinutes,
      safetyMarginMinutes: task.deadline - safetyBufferMinutes - placement.end,
    }];
  }).sort((a, b) => a.taskId.localeCompare(b.taskId));
  return {
    feasibility: "PROVEN FEASIBLE",
    safety,
    resilience: null,
    placements,
    reservePlacements: encoded.reserve.map((block) => ({
      id: block.id,
      start: intFromModel(model, block.start),
      end: intFromModel(model, block.end),
    })).sort((a, b) => a.start - b.start || a.id.localeCompare(b.id)),
    sleepPlacements: encoded.sleep.map((block) => ({
      id: block.id,
      start: intFromModel(model, block.start),
      end: intFromModel(model, block.end),
    })).sort((a, b) => a.start - b.start || a.id.localeCompare(b.id)),
    intentions: intentionResults,
    deadlineMargins,
    omissions: [],
    candidateEvidence: null,
    conflicts: [],
    assumptions,
    unlockedCommitmentIds: [...unlocked].sort(),
    stressResults: [],
  };
}

function addObjectives(request: PlanningRequest, encoded: EncodedModel, optimizer: any) {
  const { Int, If, Sum } = encoded.context;
  const absolute = (value: any) => If(value.ge(0), value, value.mul(-1));
  const shortfalls: any[] = [];
  const targetDeviation: any[] = [];
  for (const intention of request.intentions) {
    const allocated = encoded.intentionAllocations.get(intention.id);
    if (intention.minimumMinutes !== null) {
      const difference = Int.val(intention.minimumMinutes).sub(allocated);
      shortfalls.push(If(difference.gt(0), difference, Int.val(0)));
    }
    if (intention.maximumMinutes !== null) {
      const difference = allocated.sub(intention.maximumMinutes);
      shortfalls.push(If(difference.gt(0), difference, Int.val(0)));
    }
    if (intention.targetMinutes !== null) {
      targetDeviation.push(absolute(allocated.sub(intention.targetMinutes)));
    }
  }
  optimizer.minimize(Sum(Int.val(0), ...shortfalls));
  optimizer.minimize(Sum(Int.val(0), ...targetDeviation));

  const optionalUtility = [...encoded.tasks.values()]
    .filter((item) => !mandatoryTaskIds(request).has(item.task.id))
    .map((item) => If(
      item.selected,
      Int.val(PRIORITY_SCORE[item.task.priority] + IMPACT_SCORE[item.task.impact]),
      Int.val(0),
    ));
  optimizer.maximize(Sum(Int.val(0), ...optionalUtility));

  const deadlineSlack = [...encoded.tasks.values()]
    .filter((item) => item.task.deadline !== null)
    .map((item) => If(item.selected,
      Int.val(item.task.deadline!).sub(item.end), Int.val(0)));
  const stability = [...encoded.tasks.values()]
    .filter((item) => item.task.preferredStart !== null)
    .map((item) => If(
      item.selected,
      absolute(item.start.sub(item.task.preferredStart!)),
      Int.val(0),
    ));
  if (request.candidate !== null) {
    optimizer.minimize(Sum(Int.val(0), ...stability));
    optimizer.maximize(Sum(Int.val(0), ...deadlineSlack));
  } else {
    optimizer.maximize(Sum(Int.val(0), ...deadlineSlack));
    optimizer.minimize(Sum(Int.val(0), ...stability));
  }

  for (const item of [...encoded.tasks.values()]
    .sort((a, b) => a.task.id.localeCompare(b.task.id))) {
    optimizer.minimize(If(item.selected, item.start, Int.val(request.horizon.end)));
  }
}

async function solveEncoded(
  request: PlanningRequest,
  context: any,
  includeSafety: boolean,
  unlocked: Set<string>,
  optimize = true,
): Promise<SolveResult> {
  const deadline = performance.now() + request.timeoutMs;
  const remainingTimeout = () => Math.max(0, Math.floor(deadline - performance.now()));
  const encoded = encode(request, context, includeSafety, unlocked);
  const { Solver, Optimize, Bool, Implies } = context;
  const solver = new Solver();
  solver.set("timeout", request.timeoutMs);
  solver.set("random_seed", 0);
  const assumptions: any[] = [];
  const byLiteral = new Map<string, ConstraintInfo>();
  encoded.constraints.forEach((constraint, index) => {
    const literal = Bool.const(`constraint_${index}`);
    assumptions.push(literal);
    byLiteral.set(literal.sexpr(), constraint);
    solver.add(Implies(literal, constraint.expr));
  });
  const status = await solver.check(...assumptions);
  if (status === "unknown") {
    return unknownResult([`Z3 returned UNKNOWN: ${solver.reasonUnknown()}`], [...unlocked]);
  }
  if (status === "unsat") {
    let core = [...solver.unsatCore()]
      .sort((left, right) => assumptions.findIndex((item) => item.sexpr() === left.sexpr())
        - assumptions.findIndex((item) => item.sexpr() === right.sexpr()));
    let minimized = true;
    for (let index = 0; index < core.length;) {
      const timeoutMs = remainingTimeout();
      if (timeoutMs < 1) {
        minimized = false;
        break;
      }
      solver.set("timeout", timeoutMs);
      const candidate = core.filter((_literal, candidateIndex) => candidateIndex !== index);
      const candidateStatus = await solver.check(...candidate);
      if (candidateStatus === "unsat") {
        core = candidate;
      } else if (candidateStatus === "sat") {
        index += 1;
      } else {
        minimized = false;
        break;
      }
    }
    const conflicts = core
      .map((literal) => byLiteral.get(literal.sexpr()))
      .filter((item): item is ConstraintInfo => item !== undefined)
      .map(({ expr: _expr, ...item }) => mappedConflict(item));
    return {
      ...unknownResult(minimized ? [] : [
        "The bounded UNSAT-core minimization did not complete; conflicts are sound but may not be minimal.",
      ], [...unlocked]),
      feasibility: "PROVEN INFEASIBLE",
      conflicts,
    };
  }

  if (!optimize) {
    const result = resultFromModel(
      request, encoded, solver.model(), includeSafety ? "SAFE" : "TIGHT", unlocked,
    );
    const verificationErrors = verifyHardConstraints(request, result);
    if (verificationErrors.length > 0) {
      return unknownResult(
        verificationErrors.map((error) => `Internal model verification failed: ${error}`),
        [...unlocked],
      );
    }
    return result;
  }

  const optimizer = new Optimize();
  const optimizationTimeoutMs = remainingTimeout();
  if (optimizationTimeoutMs < 1) {
    return unknownResult(["The solver budget was exhausted before optimization."], [...unlocked]);
  }
  optimizer.set("timeout", optimizationTimeoutMs);
  optimizer.set("priority", "lex");
  optimizer.set("random_seed", 0);
  optimizer.add(...encoded.constraints.map((constraint) => constraint.expr));
  addObjectives(request, encoded, optimizer);
  const optimizedStatus = await optimizer.check();
  if (optimizedStatus === "unknown") {
    return unknownResult([`Z3 optimization returned UNKNOWN: ${optimizer.reasonUnknown()}`],
                         [...unlocked]);
  }
  if (optimizedStatus === "unsat") {
    return unknownResult(["Optimization contradicted a satisfiable feasibility model."],
                         [...unlocked]);
  }
  const result = resultFromModel(
    request,
    encoded,
    optimizer.model(),
    includeSafety ? "SAFE" : "TIGHT",
    unlocked,
  );
  const verificationErrors = verifyHardConstraints(request, result);
  if (verificationErrors.length > 0) {
    return unknownResult(
      verificationErrors.map((error) => `Internal model verification failed: ${error}`),
      [...unlocked],
    );
  }
  return result;
}

async function solveNominal(
  request: PlanningRequest,
  context: any,
  unlocked: Set<string>,
): Promise<SolveResult> {
  if (request.timeoutMs === 0) {
    return unknownResult(["The request supplied a zero-millisecond solver budget."],
                         [...unlocked]);
  }
  const issues = preflight(request);
  if (issues.length > 0) {
    return {
      ...unknownResult(issues, [...unlocked]),
      conflicts: preflightConflicts(request, issues),
    };
  }

  const nominal = await solveEncoded(request, context, false, unlocked);
  if (nominal.feasibility !== "PROVEN FEASIBLE") return nominal;
  nominal.assumptions = [...request.inputAssumptions];
  if (request.safetyIssues.length > 0) {
    return {
      ...nominal,
      safety: null,
      assumptions: [...request.inputAssumptions, ...request.safetyIssues],
    };
  }
  const safe = await solveEncoded(request, context, true, unlocked);
  if (safe.feasibility === "PROVEN FEASIBLE") {
    safe.assumptions = [...request.inputAssumptions];
    return safe;
  }
  if (safe.feasibility === "UNKNOWN") {
    return { ...nominal, safety: null, assumptions: safe.assumptions };
  }
  return {
    ...nominal,
    safety: "TIGHT",
    conflicts: safe.conflicts,
    assumptions: [...request.inputAssumptions,
      "Deadline feasibility is proven, but configured deadline buffers or reserve blocks do not fit.",
    ],
  };
}

async function solveProof(
  request: PlanningRequest,
  context: any,
  unlocked: Set<string>,
): Promise<SolveResult> {
  if (request.timeoutMs === 0) {
    return unknownResult(["The request supplied a zero-millisecond solver budget."], [...unlocked]);
  }
  const issues = preflight(request);
  if (issues.length > 0) {
    return { ...unknownResult(issues, [...unlocked]), conflicts: preflightConflicts(request, issues) };
  }
  const nominal = await solveEncoded(request, context, false, unlocked, false);
  if (nominal.feasibility !== "PROVEN FEASIBLE") return nominal;
  nominal.assumptions = [...request.inputAssumptions];
  if (request.safetyIssues.length > 0) return { ...nominal, safety: null,
    assumptions: [...request.inputAssumptions, ...request.safetyIssues] };
  const safe = await solveEncoded(request, context, true, unlocked, false);
  if (safe.feasibility === "PROVEN FEASIBLE") {
    safe.assumptions = [...request.inputAssumptions];
    return safe;
  }
  if (safe.feasibility === "UNKNOWN") return { ...nominal, safety: null,
    assumptions: safe.assumptions };
  return { ...nominal, safety: "TIGHT", conflicts: safe.conflicts,
    assumptions: [...request.inputAssumptions,
      "Deadline feasibility is proven, but configured deadline buffers or reserve blocks do not fit."] };
}

function comparison(baseline: SolveResult, scenario: SolveResult) {
  const baselineStarts = new Map(baseline.placements.map((item) => [item.taskId, item.start]));
  const scenarioStarts = new Map(scenario.placements.map((item) => [item.taskId, item.start]));
  const movedTaskIds = scenario.placements
    .filter((item) => baselineStarts.has(item.taskId)
      && baselineStarts.get(item.taskId) !== item.start)
    .map((item) => item.taskId)
    .sort();
  const addedTaskIds = [...scenarioStarts.keys()]
    .filter((taskId) => !baselineStarts.has(taskId)).sort();
  const droppedTaskIds = [...baselineStarts.keys()]
    .filter((taskId) => !scenarioStarts.has(taskId)).sort();
  const taskStartDeltas = movedTaskIds.map((taskId) => ({
    taskId,
    baselineStart: baselineStarts.get(taskId)!,
    scenarioStart: scenarioStarts.get(taskId)!,
    deltaMinutes: scenarioStarts.get(taskId)! - baselineStarts.get(taskId)!,
  }));
  const baselineIntentions = new Map(
    baseline.intentions.map((item) => [item.id, item.allocatedMinutes]),
  );
  const scenarioIntentions = new Map(
    scenario.intentions.map((item) => [item.id, item.allocatedMinutes]),
  );
  const intentionAllocationDeltas = [...new Set([
    ...baselineIntentions.keys(),
    ...scenarioIntentions.keys(),
  ])].sort().flatMap((intentionId) => {
    const baselineAllocatedMinutes = baselineIntentions.get(intentionId) ?? 0;
    const scenarioAllocatedMinutes = scenarioIntentions.get(intentionId) ?? 0;
    return baselineAllocatedMinutes === scenarioAllocatedMinutes ? [] : [{
      intentionId,
      baselineAllocatedMinutes,
      scenarioAllocatedMinutes,
      deltaMinutes: scenarioAllocatedMinutes - baselineAllocatedMinutes,
    }];
  });
  const reserveSummary = (result: SolveResult) => ({
    count: result.reservePlacements.length,
    minutes: result.reservePlacements.reduce(
      (total, placement) => total + placement.end - placement.start, 0,
    ),
  });
  const baselineReserve = reserveSummary(baseline);
  const scenarioReserve = reserveSummary(scenario);
  const reservePlacementDelta = {
    baselineCount: baselineReserve.count,
    scenarioCount: scenarioReserve.count,
    countDelta: scenarioReserve.count - baselineReserve.count,
    baselineMinutes: baselineReserve.minutes,
    scenarioMinutes: scenarioReserve.minutes,
    minutesDelta: scenarioReserve.minutes - baselineReserve.minutes,
  };
  const baselineStress = new Map(
    baseline.stressResults.map((item) => [item.id, item.feasibility]),
  );
  const scenarioStress = new Map(
    scenario.stressResults.map((item) => [item.id, item.feasibility]),
  );
  const stressFeasibilityTransitions = [...new Set([
    ...baselineStress.keys(),
    ...scenarioStress.keys(),
  ])].sort().map((id) => ({
    id,
    baseline: baselineStress.get(id) ?? null,
    scenario: scenarioStress.get(id) ?? null,
  }));
  let interpretation: string;
  if (baseline.feasibility === "UNKNOWN") {
    interpretation = "Baseline assurance is unknown; scenario safety cannot be attributed confidently.";
  } else if (baseline.feasibility === "PROVEN FEASIBLE"
             && scenario.feasibility === "PROVEN INFEASIBLE") {
    interpretation = "The scenario creates a conflict in a feasible baseline.";
  } else if (baseline.feasibility === "PROVEN INFEASIBLE"
             && scenario.feasibility === "PROVEN INFEASIBLE") {
    interpretation = "The baseline was already infeasible.";
  } else if (baseline.feasibility === "PROVEN FEASIBLE"
             && scenario.feasibility === "PROVEN FEASIBLE") {
    interpretation = "Both baseline and scenario are feasible; compare moved work and safety dimensions.";
  } else {
    interpretation = "Baseline and scenario have different assurance outcomes.";
  }
  return {
    interpretation,
    movedTaskIds,
    addedTaskIds,
    droppedTaskIds,
    safetyTransition: { baseline: baseline.safety, scenario: scenario.safety },
    resilienceTransition: {
      baseline: baseline.resilience,
      scenario: scenario.resilience,
    },
    taskStartDeltas,
    intentionAllocationDeltas,
    reservePlacementDelta,
    stressFeasibilityTransitions,
    projectDeltas: [],
  };
}

function projectDeltas(
  baselineRequest: PlanningRequest,
  scenarioRequest: PlanningRequest,
  baselinePortfolio: PortfolioResult,
  scenarioPortfolio: PortfolioResult,
) {
  const baselineResults = new Map(
    baselinePortfolio.projectResults.map((result) => [result.projectId, result]),
  );
  const scenarioResults = new Map(
    scenarioPortfolio.projectResults.map((result) => [result.projectId, result]),
  );
  return baselineRequest.projects.map((baselineProject) => {
    const scenarioProject = scenarioRequest.projects.find((project) =>
      project.id === baselineProject.id)!;
    const baselineResult = baselineResults.get(baselineProject.id)!;
    const scenarioResult = scenarioResults.get(baselineProject.id)!;
    return {
      projectId: baselineProject.id,
      baselineDefinitionStatus: baselineProject.definitionStatus,
      scenarioDefinitionStatus: scenarioProject.definitionStatus,
      baselineEffortMinutes: baselineProject.projectEffortMinutes,
      scenarioEffortMinutes: scenarioProject.projectEffortMinutes,
      effortDeltaMinutes: baselineProject.projectEffortMinutes === null
          || scenarioProject.projectEffortMinutes === null
        ? null : scenarioProject.projectEffortMinutes - baselineProject.projectEffortMinutes,
      baselineDeadline: baselineProject.deadline,
      scenarioDeadline: scenarioProject.deadline,
      baselineCommitment: baselineProject.commitment,
      scenarioCommitment: scenarioProject.commitment,
      baselineIsolatedFeasibility: baselineResult.isolatedFeasibility,
      scenarioIsolatedFeasibility: scenarioResult.isolatedFeasibility,
      baselinePortfolioStatus: baselineResult.portfolioStatus,
      scenarioPortfolioStatus: scenarioResult.portfolioStatus,
    };
  }).sort((left, right) => left.projectId.localeCompare(right.projectId));
}

type NegotiationResult = PlanningResponse["negotiationResults"][number];
type MaximumQuery = Extract<NegotiationQuery, {
  kind: "maximum-deadline-only-discretionary-duration"
    | "maximum-safe-discretionary-duration";
}>;

function overlaps(start: number, end: number, otherStart: number, otherEnd: number) {
  return start < otherEnd && otherStart < end;
}

class QueryBudget {
  private remainingMs: number;

  constructor(timeoutMs: number) {
    this.remainingMs = timeoutMs;
  }

  take(checksRemaining: number): number {
    if (checksRemaining < 1) return 0;
    const timeoutMs = Math.floor(this.remainingMs / checksRemaining);
    this.remainingMs -= timeoutMs;
    return timeoutMs;
  }
}

function withPhysicalReservation(
  target: PlanningRequest,
  id: string,
  start: number,
  end: number,
  timeoutMs: number,
): PlanningRequest | null {
  if (target.busy.some((block) => overlaps(start, end, block.start, block.end))) {
    return null;
  }
  return {
    ...target,
    timeoutMs,
    busy: [...target.busy, { id, start, end, kind: "scenario-reservation" }],
  };
}

function queryTarget(request: PlanningRequest, query: NegotiationQuery) {
  const target = query.scope === "scenario"
    ? applyScenario(request, request.scenario!)
    : { ...request, scenario: null };
  const unlocked = new Set(
    query.scope === "scenario" ? request.scenario!.unlockedCommitmentIds : [],
  );
  return { target, unlocked };
}

function queryUnknown(
  query: NegotiationQuery,
  assumptions: string[],
): NegotiationResult {
  const common = {
    id: query.id,
    scope: query.scope,
    feasibility: "UNKNOWN" as const,
    assumptions,
  };
  switch (query.kind) {
    case "maximum-deadline-only-discretionary-duration":
    case "maximum-safe-discretionary-duration":
      return { ...common, kind: query.kind, maximumDurationMinutes: null,
        testedStart: query.start, testedMaximumEnd: query.maximumEnd };
    case "minimum-required-work-in-window":
      return { ...common, kind: query.kind, assurance: query.assurance,
        minimumRequiredMinutes: null, testedStart: query.start, testedEnd: query.end };
    case "latest-safe-discretionary-start":
      return { ...common, kind: query.kind, latestStart: null,
        testedDurationMinutes: query.durationMinutes,
        testedEarliestStart: query.earliestStart, testedLatestEnd: query.latestEnd };
    case "minimal-commitment-unlock-set":
      return { ...common, kind: query.kind, assurance: query.assurance,
        candidateCommitmentIds: [...query.candidateCommitmentIds].sort(),
        unlockedCommitmentIds: null };
    case "maximum-project-effort":
      return { ...common, kind: query.kind, projectId: query.projectId,
        assurance: query.assurance, maximumEffortMinutes: null,
        testedMaximumEffortMinutes: query.maximumEffortMinutes };
    case "minimum-project-work-in-window":
      return { ...common, kind: query.kind, projectId: query.projectId,
        assurance: query.assurance, minimumRequiredMinutes: null,
        testedStart: query.start, testedEnd: query.end };
    case "latest-safe-project-start":
      return { ...common, kind: query.kind, projectId: query.projectId,
        latestStart: null, testedEarliestStart: query.earliestStart,
        testedLatestStart: query.latestStart };
    case "earliest-feasible-project-deadline":
      return { ...common, kind: query.kind, projectId: query.projectId,
        assurance: query.assurance, earliestDeadline: null,
        testedEarliestDeadline: query.earliestDeadline,
        testedLatestDeadline: query.latestDeadline };
    case "minimal-project-defer-set":
      return { ...common, kind: query.kind, assurance: query.assurance,
        candidateProjectIds: [...query.candidateProjectIds].sort(),
        deferredProjectIds: null, conflictProjectIds: [] };
  }
}

async function queryFeasibility(
  target: PlanningRequest,
  context: any,
  includeSafety: boolean,
  unlocked: Set<string>,
): Promise<SolveResult> {
  if (target.timeoutMs === 0) {
    return unknownResult(["The request supplied a zero-millisecond solver budget."], [...unlocked]);
  }
  const issues = preflight(target);
  if (issues.length > 0) return unknownResult(issues, [...unlocked]);
  if (includeSafety && target.safetyIssues.length > 0) {
    return unknownResult([...target.safetyIssues], [...unlocked]);
  }
  return solveEncoded(target, context, includeSafety, unlocked, false);
}

async function maximumDiscretionaryDuration(
  request: PlanningRequest,
  query: MaximumQuery,
  context: any,
): Promise<NegotiationResult> {
  const { target, unlocked } = queryTarget(request, query);
  const includeSafety = query.kind === "maximum-safe-discretionary-duration";
  const maximumUnits = Math.floor(
    (query.maximumEnd - query.start) / request.schedulingQuantumMinutes,
  );
  const maximumChecks = maximumUnits === 0
    ? 0 : 1 + Math.ceil(Math.log2(maximumUnits));
  const budget = new QueryBudget(target.timeoutMs);
  const zeroTimeoutMs = budget.take(maximumChecks + 1);
  if (zeroTimeoutMs < 1) {
    return queryUnknown(query, ["The query timeout is too small for its bounded search."]);
  }
  const zeroDurationResult = await queryFeasibility(
    { ...target, timeoutMs: zeroTimeoutMs }, context, includeSafety, unlocked,
  );
  if (zeroDurationResult.feasibility !== "PROVEN FEASIBLE") {
    if (zeroDurationResult.feasibility === "UNKNOWN") {
      return queryUnknown(query, zeroDurationResult.assumptions);
    }
    return {
      id: query.id, kind: query.kind, scope: query.scope,
      feasibility: "PROVEN INFEASIBLE", maximumDurationMinutes: null,
      testedStart: query.start, testedMaximumEnd: query.maximumEnd,
      assumptions: zeroDurationResult.assumptions,
    };
  }
  if (maximumUnits === 0) {
    return { id: query.id, kind: query.kind, scope: query.scope,
      feasibility: "PROVEN FEASIBLE", maximumDurationMinutes: 0,
      testedStart: query.start, testedMaximumEnd: query.maximumEnd,
      assumptions: target.inputAssumptions };
  }

  let checksRemaining = maximumChecks;
  const check = async (units: number): Promise<SolveResult> => {
    const timeoutMs = budget.take(checksRemaining);
    checksRemaining -= 1;
    if (timeoutMs < 1) {
      return unknownResult(["The query timeout was exhausted during its bounded search."]);
    }
    const durationMinutes = units * request.schedulingQuantumMinutes;
    const end = query.start + durationMinutes;
    const candidate = withPhysicalReservation(
      target, `negotiation:${query.id}`, query.start, end, timeoutMs,
    );
    if (candidate === null) {
      return {
        ...unknownResult([]),
        feasibility: "PROVEN INFEASIBLE",
      };
    }
    return solveEncoded(candidate, context, includeSafety, unlocked, false);
  };

  let low = 0;
  let high = maximumUnits;
  const searchAssumptions = new Set<string>();
  const maximum = await check(high);
  if (maximum.feasibility === "UNKNOWN") {
    return queryUnknown(query, maximum.assumptions);
  }
  if (maximum.feasibility === "PROVEN FEASIBLE") {
    return { id: query.id, kind: query.kind, scope: query.scope,
      feasibility: "PROVEN FEASIBLE",
      maximumDurationMinutes: high * request.schedulingQuantumMinutes,
      testedStart: query.start, testedMaximumEnd: query.maximumEnd,
      assumptions: target.inputAssumptions };
  }
  maximum.assumptions.forEach((assumption) => searchAssumptions.add(assumption));

  while (low + 1 < high) {
    const middle = Math.floor((low + high) / 2);
    const result = await check(middle);
    if (result.feasibility === "UNKNOWN") {
      return queryUnknown(query, result.assumptions);
    }
    if (result.feasibility === "PROVEN FEASIBLE") low = middle;
    else {
      high = middle;
      result.assumptions.forEach((assumption) => searchAssumptions.add(assumption));
    }
  }
  return { id: query.id, kind: query.kind, scope: query.scope,
    feasibility: "PROVEN FEASIBLE",
    maximumDurationMinutes: low * request.schedulingQuantumMinutes,
    testedStart: query.start, testedMaximumEnd: query.maximumEnd,
    assumptions: [...target.inputAssumptions, ...searchAssumptions] };
}

async function minimumRequiredWorkInWindow(
  request: PlanningRequest,
  query: Extract<NegotiationQuery, {
    kind: "minimum-required-work-in-window" | "minimum-project-work-in-window";
  }>,
  context: any,
): Promise<NegotiationResult> {
  const selected = queryTarget(request, query);
  const target = query.kind === "minimum-project-work-in-window"
    ? portfolioScopedRequest(selected.target) : selected.target;
  const { unlocked } = selected;
  if (target.timeoutMs === 0 || preflight(target).length > 0
      || (query.assurance === "safe" && target.safetyIssues.length > 0)) {
    return queryUnknown(query, target.timeoutMs === 0
      ? ["The request supplied a zero-millisecond solver budget."]
      : [...preflight(target), ...(query.assurance === "safe" ? target.safetyIssues : [])]);
  }
  const encoded = encode(target, context, query.assurance === "safe", unlocked);
  const { Optimize, If, Int, Sum } = context;
  const overlapTerms = [...encoded.tasks.values()]
    .filter((item) => query.kind !== "minimum-project-work-in-window"
      || item.task.projectId === query.projectId)
    .map((item) => {
    const overlapStart = If(item.start.ge(query.start), item.start, Int.val(query.start));
    const overlapEnd = If(item.end.le(query.end), item.end, Int.val(query.end));
    return If(item.selected.and(item.end.gt(query.start)).and(item.start.lt(query.end)),
      overlapEnd.sub(overlapStart), Int.val(0));
  });
  const total = Sum(Int.val(0), ...overlapTerms);
  const budget = new QueryBudget(target.timeoutMs);
  const optimizationTimeoutMs = budget.take(2);
  if (optimizationTimeoutMs < 1) {
    return queryUnknown(query, ["The query timeout is too small for optimization verification."]);
  }
  const optimizer = new Optimize();
  optimizer.set("timeout", optimizationTimeoutMs);
  optimizer.set("priority", "lex");
  optimizer.set("random_seed", 0);
  optimizer.add(...encoded.constraints.map((constraint) => constraint.expr));
  optimizer.minimize(total);
  const status = await optimizer.check();
  if (status === "unknown") {
    return queryUnknown(query, [`Z3 optimization returned UNKNOWN: ${optimizer.reasonUnknown()}`]);
  }
  if (status === "unsat") {
    return minimumWorkResult(query, "PROVEN INFEASIBLE", null, []);
  }
  const model = optimizer.model();
  const minimumRequiredMinutes = intFromModel(model, total);
  const witness = resultFromModel(
    target,
    encoded,
    model,
    query.assurance === "safe" ? "SAFE" : "TIGHT",
    unlocked,
  );
  const verificationErrors = verifyHardConstraints(target, witness);
  const witnessedMinutes = witness.placements.reduce((sum, placement) => sum + Math.max(
    0,
    Math.min(placement.end, query.end) - Math.max(placement.start, query.start),
  ), 0);
  if (witnessedMinutes !== minimumRequiredMinutes) {
    verificationErrors.push(
      `minimum-work objective is ${minimumRequiredMinutes}, but its witness contains ${witnessedMinutes}`,
    );
  }
  if (verificationErrors.length > 0) {
    return queryUnknown(query, verificationErrors.map((error) =>
      `Internal optimizer witness verification failed: ${error}`));
  }

  const verificationTimeoutMs = budget.take(1);
  if (verificationTimeoutMs < 1) {
    return queryUnknown(query, ["The query timeout was exhausted before objective verification."]);
  }
  const verifier = new context.Solver();
  verifier.set("timeout", verificationTimeoutMs);
  verifier.set("random_seed", 0);
  verifier.add(...encoded.constraints.map((constraint) => constraint.expr));
  verifier.add(total.lt(minimumRequiredMinutes));
  const verificationStatus = await verifier.check();
  if (verificationStatus === "unknown") {
    return queryUnknown(query, [
      `Z3 objective verification returned UNKNOWN: ${verifier.reasonUnknown()}`,
    ]);
  }
  if (verificationStatus === "sat") {
    return queryUnknown(query, [
      "Internal objective verification found a lower minimum-required-work value.",
    ]);
  }
  return minimumWorkResult(query, "PROVEN FEASIBLE", minimumRequiredMinutes,
    target.inputAssumptions);
}

function minimumWorkResult(
  query: Extract<NegotiationQuery, {
    kind: "minimum-required-work-in-window" | "minimum-project-work-in-window";
  }>,
  feasibility: "PROVEN FEASIBLE" | "PROVEN INFEASIBLE",
  minimumRequiredMinutes: number | null,
  assumptions: string[],
): NegotiationResult {
  const common = {
    id: query.id, scope: query.scope, assurance: query.assurance, feasibility,
    minimumRequiredMinutes, testedStart: query.start, testedEnd: query.end, assumptions,
  };
  return query.kind === "minimum-project-work-in-window"
    ? { ...common, kind: query.kind, projectId: query.projectId }
    : { ...common, kind: query.kind };
}

async function latestSafeDiscretionaryStart(
  request: PlanningRequest,
  query: Extract<NegotiationQuery, { kind: "latest-safe-discretionary-start" }>,
  context: any,
): Promise<NegotiationResult> {
  const { target, unlocked } = queryTarget(request, query);
  const quantum = request.schedulingQuantumMinutes;
  const first = Math.ceil(query.earliestStart / quantum) * quantum;
  const last = Math.floor((query.latestEnd - query.durationMinutes) / quantum) * quantum;
  const checks = last < first ? 0 : Math.floor((last - first) / quantum) + 1;
  if (checks > 4096) {
    return queryUnknown(query, ["The latest-start search exceeds the bounded check limit."]);
  }
  if (checks === 0) {
    return { id: query.id, kind: query.kind, scope: query.scope,
      feasibility: "PROVEN INFEASIBLE", latestStart: null,
      testedDurationMinutes: query.durationMinutes,
      testedEarliestStart: query.earliestStart, testedLatestEnd: query.latestEnd,
      assumptions: [] };
  }
  const budget = new QueryBudget(target.timeoutMs);
  if (Math.floor(target.timeoutMs / checks) < 1) {
    return queryUnknown(query, ["The query timeout is too small for its bounded search."]);
  }
  let checksRemaining = checks;
  const searchAssumptions = new Set<string>();
  for (let start = last; start >= first; start -= quantum) {
    const timeoutMs = budget.take(checksRemaining);
    checksRemaining -= 1;
    if (timeoutMs < 1) {
      return queryUnknown(query, ["The query timeout was exhausted during its bounded search."]);
    }
    const candidate = withPhysicalReservation(
      target,
      `negotiation:${query.id}`,
      start,
      start + query.durationMinutes,
      timeoutMs,
    );
    if (candidate === null) continue;
    const result = await queryFeasibility(candidate, context, true, unlocked);
    if (result.feasibility === "UNKNOWN") return queryUnknown(query, result.assumptions);
    if (result.feasibility === "PROVEN FEASIBLE") {
      return { id: query.id, kind: query.kind, scope: query.scope,
        feasibility: "PROVEN FEASIBLE", latestStart: start,
        testedDurationMinutes: query.durationMinutes,
        testedEarliestStart: query.earliestStart, testedLatestEnd: query.latestEnd,
        assumptions: [...target.inputAssumptions, ...searchAssumptions] };
    }
    result.assumptions.forEach((assumption) => searchAssumptions.add(assumption));
  }
  return { id: query.id, kind: query.kind, scope: query.scope,
    feasibility: "PROVEN INFEASIBLE", latestStart: null,
    testedDurationMinutes: query.durationMinutes,
    testedEarliestStart: query.earliestStart, testedLatestEnd: query.latestEnd,
    assumptions: [...searchAssumptions] };
}

function combinations(values: string[], size: number): string[][] {
  const output: string[][] = [];
  const visit = (start: number, chosen: string[]) => {
    if (chosen.length === size) {
      output.push([...chosen]);
      return;
    }
    for (let index = start; index <= values.length - (size - chosen.length); index += 1) {
      chosen.push(values[index]!);
      visit(index + 1, chosen);
      chosen.pop();
    }
  };
  visit(0, []);
  return output;
}

async function minimalCommitmentUnlockSet(
  request: PlanningRequest,
  query: Extract<NegotiationQuery, { kind: "minimal-commitment-unlock-set" }>,
  context: any,
): Promise<NegotiationResult> {
  const { target, unlocked: alreadyUnlocked } = queryTarget(request, query);
  const candidates = [...query.candidateCommitmentIds].sort();
  if (candidates.length > 16) {
    return queryUnknown(query, ["The unlock search exceeds the bounded candidate limit."]);
  }
  const checkCount = 2 ** candidates.length;
  const budget = new QueryBudget(target.timeoutMs);
  if (Math.floor(target.timeoutMs / checkCount) < 1) {
    return queryUnknown(query, ["The query timeout is too small for its bounded search."]);
  }
  let checksRemaining = checkCount;
  const searchAssumptions = new Set<string>();
  for (let size = 0; size <= candidates.length; size += 1) {
    for (const candidate of combinations(candidates, size)) {
      const timeoutMs = budget.take(checksRemaining);
      checksRemaining -= 1;
      if (timeoutMs < 1) {
        return queryUnknown(query, ["The query timeout was exhausted during its bounded search."]);
      }
      const unlocked = new Set([...alreadyUnlocked, ...candidate]);
      const result = await queryFeasibility(
        { ...target, timeoutMs }, context, query.assurance === "safe", unlocked,
      );
      if (result.feasibility === "UNKNOWN") return queryUnknown(query, result.assumptions);
      if (result.feasibility === "PROVEN FEASIBLE") {
        return { id: query.id, kind: query.kind, scope: query.scope,
          assurance: query.assurance, feasibility: "PROVEN FEASIBLE",
          candidateCommitmentIds: candidates, unlockedCommitmentIds: candidate,
          assumptions: [...target.inputAssumptions, ...searchAssumptions] };
      }
      result.assumptions.forEach((assumption) => searchAssumptions.add(assumption));
    }
  }
  return { id: query.id, kind: query.kind, scope: query.scope,
    assurance: query.assurance, feasibility: "PROVEN INFEASIBLE",
    candidateCommitmentIds: candidates, unlockedCommitmentIds: null,
    assumptions: [...searchAssumptions] };
}

function applyProjectChanges(
  request: PlanningRequest,
  changes: NonNullable<PlanningRequest["scenario"]>["projectChanges"],
) {
  return applyScenario(request, {
    id: "negotiation-project-overlay",
    reservations: [],
    unlockedCommitmentIds: [],
    estimateChanges: [],
    intentionChanges: [],
    projectChanges: changes,
  });
}

function portfolioScopedRequest(request: PlanningRequest): PlanningRequest {
  const ready = request.projects.filter((project) => project.commitment === "COMMITTED"
    && project.definitionStatus !== "INCOMPLETE");
  const fixedIds = request.tasks.filter((task) => task.fixedStart !== null).map((task) => task.id);
  return scopedRequest(request, taskClosure(request, [
    ...ready.flatMap((project) => request.tasks
      .filter((task) => task.projectId === project.id).map((task) => task.id)),
    ...fixedIds,
  ]));
}

async function projectQueryFeasibility(
  request: PlanningRequest,
  context: any,
  assurance: "deadline-only" | "safe",
  unlocked: Set<string>,
) {
  return queryFeasibility(portfolioScopedRequest(request), context, assurance === "safe", unlocked);
}

async function maximumProjectEffort(
  request: PlanningRequest,
  query: Extract<NegotiationQuery, { kind: "maximum-project-effort" }>,
  context: any,
): Promise<NegotiationResult> {
  const { target, unlocked } = queryTarget(request, query);
  const project = target.projects.find((item) => item.id === query.projectId)!;
  if (project.defaultWorkMode === null || project.planningChunkMinutes === null
      || project.estimateConfidence === null) {
    return queryUnknown(query, ["Maximum project effort requires complete coarse metadata."]);
  }
  const quantum = request.schedulingQuantumMinutes;
  let low = Math.ceil(project.explicitEffortMinutes / quantum);
  let high = Math.floor(query.maximumEffortMinutes / quantum);
  const checks = high < low ? 1 : 2 + Math.ceil(Math.log2(high - low + 1));
  const budget = new QueryBudget(target.timeoutMs);
  const check = async (units: number) => {
    const timeoutMs = budget.take(Math.max(1, checks));
    if (timeoutMs < 1) return unknownResult(["The query timeout was exhausted."]);
    const candidate = applyProjectChanges({ ...target, timeoutMs }, [{
      projectId: query.projectId,
      projectEffortMinutes: units * quantum,
    }]);
    return projectQueryFeasibility(candidate, context, query.assurance, unlocked);
  };
  const minimum = await check(low);
  if (minimum.feasibility !== "PROVEN FEASIBLE") {
    return minimum.feasibility === "UNKNOWN" ? queryUnknown(query, minimum.assumptions) : {
      id: query.id, kind: query.kind, scope: query.scope, projectId: query.projectId,
      assurance: query.assurance, feasibility: "PROVEN INFEASIBLE",
      maximumEffortMinutes: null, testedMaximumEffortMinutes: query.maximumEffortMinutes,
      assumptions: minimum.assumptions,
    };
  }
  while (low < high) {
    const middle = Math.ceil((low + high) / 2);
    const result = await check(middle);
    if (result.feasibility === "UNKNOWN") return queryUnknown(query, result.assumptions);
    if (result.feasibility === "PROVEN FEASIBLE") low = middle;
    else high = middle - 1;
  }
  return { id: query.id, kind: query.kind, scope: query.scope, projectId: query.projectId,
    assurance: query.assurance, feasibility: "PROVEN FEASIBLE",
    maximumEffortMinutes: low * quantum,
    testedMaximumEffortMinutes: query.maximumEffortMinutes,
    assumptions: target.inputAssumptions };
}

async function latestProjectStart(
  request: PlanningRequest,
  query: Extract<NegotiationQuery, { kind: "latest-safe-project-start" }>,
  context: any,
): Promise<NegotiationResult> {
  const { target, unlocked } = queryTarget(request, query);
  const quantum = request.schedulingQuantumMinutes;
  const first = Math.ceil(query.earliestStart / quantum) * quantum;
  const last = Math.floor(query.latestStart / quantum) * quantum;
  const checks = last < first ? 0 : Math.floor((last - first) / quantum) + 1;
  if (checks === 0 || checks > 4096) {
    return checks > 4096 ? queryUnknown(query, ["The project-start search exceeds the bounded check limit."])
      : { id: query.id, kind: query.kind, scope: query.scope, projectId: query.projectId,
        feasibility: "PROVEN INFEASIBLE", latestStart: null,
        testedEarliestStart: query.earliestStart, testedLatestStart: query.latestStart,
        assumptions: [] };
  }
  const budget = new QueryBudget(target.timeoutMs);
  for (let start = last, remaining = checks; start >= first; start -= quantum, remaining -= 1) {
    const timeoutMs = budget.take(remaining);
    if (timeoutMs < 1) return queryUnknown(query, ["The project-start search exhausted its budget."]);
    const candidate = { ...target, timeoutMs, tasks: target.tasks.map((task) =>
      task.projectId === query.projectId && task.fixedStart === null
        ? { ...task, releaseTime: Math.max(task.releaseTime ?? start, start) } : task) };
    const result = await projectQueryFeasibility(candidate, context, "safe", unlocked);
    if (result.feasibility === "UNKNOWN") return queryUnknown(query, result.assumptions);
    if (result.feasibility === "PROVEN FEASIBLE") {
      return { id: query.id, kind: query.kind, scope: query.scope, projectId: query.projectId,
        feasibility: "PROVEN FEASIBLE", latestStart: start,
        testedEarliestStart: query.earliestStart, testedLatestStart: query.latestStart,
        assumptions: target.inputAssumptions };
    }
  }
  return { id: query.id, kind: query.kind, scope: query.scope, projectId: query.projectId,
    feasibility: "PROVEN INFEASIBLE", latestStart: null,
    testedEarliestStart: query.earliestStart, testedLatestStart: query.latestStart,
    assumptions: [] };
}

async function earliestProjectDeadline(
  request: PlanningRequest,
  query: Extract<NegotiationQuery, { kind: "earliest-feasible-project-deadline" }>,
  context: any,
): Promise<NegotiationResult> {
  const { target, unlocked } = queryTarget(request, query);
  const quantum = request.schedulingQuantumMinutes;
  let low = Math.ceil(query.earliestDeadline / quantum);
  let high = Math.floor(query.latestDeadline / quantum);
  const checks = high < low ? 0 : 2 + Math.ceil(Math.log2(high - low + 1));
  if (checks === 0) return { id: query.id, kind: query.kind, scope: query.scope,
    projectId: query.projectId, assurance: query.assurance,
    feasibility: "PROVEN INFEASIBLE", earliestDeadline: null,
    testedEarliestDeadline: query.earliestDeadline, testedLatestDeadline: query.latestDeadline,
    assumptions: [] };
  const budget = new QueryBudget(target.timeoutMs);
  const check = async (units: number) => {
    const timeoutMs = budget.take(checks);
    if (timeoutMs < 1) return unknownResult(["The deadline search exhausted its budget."]);
    return projectQueryFeasibility(applyProjectChanges({ ...target, timeoutMs }, [{
      projectId: query.projectId, deadline: units * quantum,
    }]), context, query.assurance, unlocked);
  };
  const upper = await check(high);
  if (upper.feasibility !== "PROVEN FEASIBLE") {
    return upper.feasibility === "UNKNOWN" ? queryUnknown(query, upper.assumptions) : {
      id: query.id, kind: query.kind, scope: query.scope, projectId: query.projectId,
      assurance: query.assurance, feasibility: "PROVEN INFEASIBLE", earliestDeadline: null,
      testedEarliestDeadline: query.earliestDeadline, testedLatestDeadline: query.latestDeadline,
      assumptions: upper.assumptions,
    };
  }
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    const result = await check(middle);
    if (result.feasibility === "UNKNOWN") return queryUnknown(query, result.assumptions);
    if (result.feasibility === "PROVEN FEASIBLE") high = middle;
    else low = middle + 1;
  }
  return { id: query.id, kind: query.kind, scope: query.scope, projectId: query.projectId,
    assurance: query.assurance, feasibility: "PROVEN FEASIBLE", earliestDeadline: low * quantum,
    testedEarliestDeadline: query.earliestDeadline, testedLatestDeadline: query.latestDeadline,
    assumptions: target.inputAssumptions };
}

async function minimalProjectDeferSet(
  request: PlanningRequest,
  query: Extract<NegotiationQuery, { kind: "minimal-project-defer-set" }>,
  context: any,
): Promise<NegotiationResult> {
  const { target, unlocked } = queryTarget(request, query);
  const candidates = [...query.candidateProjectIds].sort();
  if (candidates.length > 16) {
    return queryUnknown(query, ["The project-defer search exceeds the bounded candidate limit."]);
  }
  const budget = new QueryBudget(target.timeoutMs);
  const checkCount = 2 ** candidates.length;
  let remaining = checkCount;
  let lastConflicts: string[] = [];
  for (let size = 0; size <= candidates.length; size += 1) {
    for (const deferred of combinations(candidates, size)) {
      const timeoutMs = budget.take(remaining--);
      if (timeoutMs < 1) return queryUnknown(query, ["The project-defer search exhausted its budget."]);
      const candidate = applyProjectChanges({ ...target, timeoutMs }, deferred.map((projectId) => ({
        projectId, commitment: "UNCOMMITTED" as const,
      })));
      const result = await projectQueryFeasibility(candidate, context, query.assurance, unlocked);
      if (result.feasibility === "UNKNOWN") return queryUnknown(query, result.assumptions);
      const currentConflicts = [...new Set(
        result.conflicts.flatMap((conflict) => conflict.projectIds),
      )].sort();
      if (currentConflicts.length > 0) lastConflicts = currentConflicts;
      if (result.feasibility === "PROVEN FEASIBLE") {
        return { id: query.id, kind: query.kind, scope: query.scope,
          assurance: query.assurance, feasibility: "PROVEN FEASIBLE",
          candidateProjectIds: candidates, deferredProjectIds: deferred,
          conflictProjectIds: lastConflicts, assumptions: target.inputAssumptions };
      }
    }
  }
  return { id: query.id, kind: query.kind, scope: query.scope,
    assurance: query.assurance, feasibility: "PROVEN INFEASIBLE",
    candidateProjectIds: candidates, deferredProjectIds: null,
    conflictProjectIds: lastConflicts, assumptions: [] };
}

async function classifyResilience(
  request: PlanningRequest,
  target: PlanningRequest,
  result: SolveResult,
  context: any,
  unlocked: Set<string>,
) {
  if (result.feasibility !== "PROVEN FEASIBLE" || request.stressProfiles.length === 0) return;
  const stressResults = [];
  for (const profile of request.stressProfiles) {
    const stressed = applyScenario(target, profile.scenario);
    const stressedResult = await queryFeasibility(
      stressed,
      context,
      false,
      new Set([...unlocked, ...profile.scenario.unlockedCommitmentIds]),
    );
    stressResults.push({ id: profile.id, feasibility: stressedResult.feasibility });
  }
  result.stressResults = stressResults;
  result.resilience = stressResults.some((item) => item.feasibility === "UNKNOWN")
    ? null
    : stressResults.every((item) => item.feasibility === "PROVEN FEASIBLE")
      ? "RESILIENT"
      : "FRAGILE";
}

function taskClosure(request: PlanningRequest, initialIds: Iterable<string>): Set<string> {
  const tasks = new Map(request.tasks.map((task) => [task.id, task]));
  const included = new Set(initialIds);
  const pending = [...included];
  while (pending.length > 0) {
    const task = tasks.get(pending.pop()!);
    for (const prerequisiteId of task?.prerequisiteIds ?? []) {
      if (!included.has(prerequisiteId)) {
        included.add(prerequisiteId);
        pending.push(prerequisiteId);
      }
    }
  }
  return included;
}

function scopedRequest(request: PlanningRequest, taskIds: Set<string>): PlanningRequest {
  const tasks = request.tasks.filter((task) => taskIds.has(task.id));
  const projectIds = new Set(tasks.flatMap((task) => task.projectId === null ? [] : [task.projectId]));
  return {
    ...request,
    tasks,
    projects: request.projects.filter((project) => projectIds.has(project.id)),
    intentions: request.intentions.map((intention) => ({
      ...intention,
      matchedTaskIds: intention.matchedTaskIds.filter((taskId) => taskIds.has(taskId)),
    })),
    stressProfiles: [],
    scenario: null,
    negotiationQueries: [],
  };
}

function projectTaskScope(request: PlanningRequest, projectId: string) {
  const owned = request.tasks.filter((task) => task.projectId === projectId).map((task) => task.id);
  const dependencyIds = taskClosure(request, owned);
  const borrowed = [...dependencyIds].filter((taskId) =>
    request.tasks.find((task) => task.id === taskId)?.projectId !== projectId).sort();
  const fixed = request.tasks.filter((task) => task.fixedStart !== null).map((task) => task.id);
  const all = taskClosure(request, [...dependencyIds, ...fixed]);
  const borrowedProjects = [...new Set(borrowed.flatMap((taskId) => {
    const projectId = request.tasks.find((task) => task.id === taskId)?.projectId;
    return projectId === null || projectId === undefined ? [] : [projectId];
  }))].sort();
  return { request: scopedRequest(request, all), borrowed, borrowedProjects };
}

function minimumMargin(
  margins: SolveResult["deadlineMargins"],
  projectId: string,
  field: "hardDeadlineMarginMinutes" | "safetyMarginMinutes",
) {
  const values = margins.filter((margin) => margin.projectId === projectId)
    .map((margin) => margin[field]);
  return values.length === 0 ? null : Math.min(...values);
}

type PortfolioResult = NonNullable<PlanningResponse["baselinePortfolio"]>;

async function solvePortfolio(
  request: PlanningRequest,
  context: any,
  unlocked: Set<string>,
  existingGlobal?: SolveResult,
): Promise<PortfolioResult> {
  const committed = request.projects.filter((project) => project.commitment === "COMMITTED");
  const ready = committed.filter((project) => project.definitionStatus !== "INCOMPLETE");
  const fixedIds = request.tasks.filter((task) => task.fixedStart !== null).map((task) => task.id);
  const portfolioIds = taskClosure(request, [
    ...ready.flatMap((project) => request.tasks
      .filter((task) => task.projectId === project.id).map((task) => task.id)),
    ...fixedIds,
  ]);
  const portfolioRequest = scopedRequest(request, portfolioIds);
  const sameTaskScope = portfolioRequest.tasks.length === request.tasks.length
    && portfolioRequest.tasks.every((task, index) => task.id === request.tasks[index]?.id);
  const globalResult = sameTaskScope && existingGlobal !== undefined
    ? existingGlobal : await solveProof(portfolioRequest, context, unlocked);
  const conflictTaskIds = [...new Set(globalResult.conflicts.flatMap((conflict) => conflict.taskIds))]
    .sort();
  const conflictProjectIds = [...new Set(
    globalResult.conflicts.flatMap((conflict) => conflict.projectIds),
  )].sort();
  const projectResults: PortfolioResult["projectResults"] = [];

  for (const project of [...request.projects].sort((a, b) => a.id.localeCompare(b.id))) {
    if (project.commitment === "UNCOMMITTED") {
      projectResults.push({
        projectId: project.id, definitionStatus: project.definitionStatus,
        commitment: project.commitment, isolatedFeasibility: "UNCOMMITTED", proofKind: null,
        isolatedResult: null, borrowedPrerequisiteTaskIds: [],
        borrowedPrerequisiteProjectIds: [], portfolioStatus: "UNCOMMITTED",
        hardDeadlineMarginMinutes: null, safetyMarginMinutes: null,
        conflictTaskIds: [], conflictProjectIds: [],
      });
      continue;
    }
    if (project.definitionStatus === "INCOMPLETE") {
      projectResults.push({
        projectId: project.id, definitionStatus: project.definitionStatus,
        commitment: project.commitment, isolatedFeasibility: "UNKNOWN", proofKind: null,
        isolatedResult: null, borrowedPrerequisiteTaskIds: [],
        borrowedPrerequisiteProjectIds: [], portfolioStatus: "UNKNOWN",
        hardDeadlineMarginMinutes: null, safetyMarginMinutes: null,
        conflictTaskIds: [], conflictProjectIds: [],
      });
      continue;
    }
    const scope = projectTaskScope(request, project.id);
    const samePortfolioScope = scope.request.tasks.length === portfolioRequest.tasks.length
      && scope.request.tasks.every((task, index) => task.id === portfolioRequest.tasks[index]?.id);
    const isolatedResult = samePortfolioScope
      ? globalResult : await solveProof(scope.request, context, unlocked);
    const isolatedFeasibility = isolatedResult.feasibility === "PROVEN FEASIBLE"
      ? "FEASIBLE" as const
      : isolatedResult.feasibility === "PROVEN INFEASIBLE" ? "INFEASIBLE" as const : "UNKNOWN" as const;
    const involved = conflictProjectIds.includes(project.id);
    const portfolioStatus = globalResult.feasibility === "PROVEN FEASIBLE"
      ? (globalResult.safety === "SAFE" ? "FITS" as const : "TIGHT" as const)
      : globalResult.feasibility === "PROVEN INFEASIBLE" && involved
        ? "CONFLICT-INVOLVED" as const : "UNKNOWN" as const;
    projectResults.push({
      projectId: project.id, definitionStatus: project.definitionStatus,
      commitment: project.commitment, isolatedFeasibility,
      proofKind: isolatedFeasibility === "FEASIBLE"
        ? (project.definitionStatus === "COARSE"
          ? "CAPACITY FEASIBLE" as const : "STRUCTURALLY FEASIBLE" as const)
        : null,
      isolatedResult,
      borrowedPrerequisiteTaskIds: scope.borrowed,
      borrowedPrerequisiteProjectIds: scope.borrowedProjects,
      portfolioStatus,
      hardDeadlineMarginMinutes: minimumMargin(globalResult.deadlineMargins, project.id,
        "hardDeadlineMarginMinutes"),
      safetyMarginMinutes: minimumMargin(globalResult.deadlineMargins, project.id,
        "safetyMarginMinutes"),
      conflictTaskIds: conflictTaskIds.filter((taskId) =>
        request.tasks.find((task) => task.id === taskId)?.projectId === project.id),
      conflictProjectIds: involved ? conflictProjectIds : [],
    });
  }
  const modeledProjectIds = ready.map((project) => project.id).sort();
  const excludedProjectIds = request.projects.filter((project) =>
    !modeledProjectIds.includes(project.id)).map((project) => project.id).sort();
  return {
    definitionStatus: committed.some((project) => project.definitionStatus === "INCOMPLETE")
      ? "INCOMPLETE" : "COMPLETE",
    feasibility: globalResult.feasibility,
    safety: globalResult.safety,
    modeledProjectIds,
    excludedProjectIds,
    modeledSubset: excludedProjectIds.length > 0,
    globalResult,
    projectResults,
  };
}

export async function solvePlanningRequest(request: PlanningRequest): Promise<PlanningResponse> {
  const api = await init();
  try {
    const context = new api.Context("lifeos");
    const effectiveRequest = applyCandidateEdits(request);
    let baseline = await solveNominal(effectiveRequest, context, new Set());
    await classifyResilience(effectiveRequest, effectiveRequest, baseline, context, new Set());
    baseline = decorateCandidateResult(request, effectiveRequest, baseline);
    const baselinePortfolio = await solvePortfolio(effectiveRequest, context, new Set(), baseline);

    let scenario: SolveResult | null = null;
    let scenarioRequest: PlanningRequest | null = null;
    let scenarioPortfolio: PortfolioResult | null = null;
    if (effectiveRequest.scenario !== null) {
      const baselineStarts = new Map(
        baseline.placements.map((placement) => [placement.taskId, placement.start]),
      );
      const appliedScenario = applyScenario(effectiveRequest, effectiveRequest.scenario);
      scenarioRequest = {
        ...appliedScenario,
        tasks: appliedScenario.tasks.map((task) => ({
          ...task,
          preferredStart: baselineStarts.get(task.id) ?? task.preferredStart,
        })),
      };
      scenario = await solveNominal(
        scenarioRequest,
        context,
        new Set(effectiveRequest.scenario.unlockedCommitmentIds),
      );
      await classifyResilience(
        effectiveRequest,
        scenarioRequest,
        scenario,
        context,
        new Set(effectiveRequest.scenario.unlockedCommitmentIds),
      );
      scenario = decorateCandidateResult(request, scenarioRequest, scenario);
      scenarioPortfolio = await solvePortfolio(
        scenarioRequest, context, new Set(effectiveRequest.scenario.unlockedCommitmentIds), scenario,
      );
    }
    const negotiationResults = [];
    for (const query of effectiveRequest.negotiationQueries) {
      switch (query.kind) {
        case "maximum-deadline-only-discretionary-duration":
        case "maximum-safe-discretionary-duration":
          negotiationResults.push(await maximumDiscretionaryDuration(effectiveRequest, query, context));
          break;
        case "minimum-required-work-in-window":
        case "minimum-project-work-in-window":
          negotiationResults.push(await minimumRequiredWorkInWindow(effectiveRequest, query, context));
          break;
        case "latest-safe-discretionary-start":
          negotiationResults.push(await latestSafeDiscretionaryStart(effectiveRequest, query, context));
          break;
        case "minimal-commitment-unlock-set":
          negotiationResults.push(await minimalCommitmentUnlockSet(effectiveRequest, query, context));
          break;
        case "maximum-project-effort":
          negotiationResults.push(await maximumProjectEffort(effectiveRequest, query, context));
          break;
        case "latest-safe-project-start":
          negotiationResults.push(await latestProjectStart(effectiveRequest, query, context));
          break;
        case "earliest-feasible-project-deadline":
          negotiationResults.push(await earliestProjectDeadline(effectiveRequest, query, context));
          break;
        case "minimal-project-defer-set":
          negotiationResults.push(await minimalProjectDeferSet(effectiveRequest, query, context));
          break;
      }
    }
    return responseEnvelope(request.requestId, {
      candidateIdentity: candidateIdentity(request),
      status: "ok",
      baseline,
      scenario,
      baselinePortfolio,
      scenarioPortfolio,
      comparison: scenario === null ? null : {
        ...comparison(baseline, scenario),
        projectDeltas: projectDeltas(effectiveRequest, scenarioRequest!, baselinePortfolio,
          scenarioPortfolio!),
      },
      negotiationResults,
      errors: [],
    });
  } finally {
    await killThreads(api.em);
  }
}

export function internalErrorResponse(request: PlanningRequest, error: unknown): PlanningResponse {
  return responseEnvelope(request.requestId, {
    candidateIdentity: candidateIdentity(request),
    status: "internal-error",
    baseline: null,
    scenario: null,
    baselinePortfolio: null,
    scenarioPortfolio: null,
    comparison: null,
    negotiationResults: [],
    errors: [{ path: "", message: error instanceof Error ? error.message : String(error) }],
  });
}

export { IMPACT_SCORE, PRIORITY_SCORE, SOLVER_VERSION };
