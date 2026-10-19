import { z } from "zod";

export const PROTOCOL_VERSION = "lifeos-planning/v3" as const;
export const SOLVER_VERSION = "lifeos-z3/0.3.0+z3-solver/5.2.0" as const;

const id = z.string().min(1);
const minute = z.number().int();
const duration = z.number().int().positive();

export const evidenceSchema = z.object({
  sourceId: id,
  kind: z.string().min(1),
  detail: z.string().min(1).optional(),
}).strict();

export const intervalSchema = z.object({
  id,
  start: minute,
  end: minute,
  modes: z.array(z.string().min(1)).optional(),
  kind: z.enum([
    "availability",
    "calendar",
    "travel",
    "commitment",
    "scenario-reservation",
  ]),
  evidence: evidenceSchema.optional(),
}).refine((value) => value.end > value.start, {
  message: "interval end must be after start",
});

export const taskSchema = z.object({
  id,
  projectId: id.nullable(),
  durationMinutes: duration.nullable(),
  workMode: z.string().min(1),
  deadline: minute.nullable(),
  deadlineSource: z.enum(["task", "project"]).nullable().default(null),
  releaseTime: minute.nullable().default(null),
  fixedStart: minute.nullable(),
  preferredStart: minute.nullable(),
  prerequisiteIds: z.array(id),
  state: z.enum(["TODO", "NEXT", "WAITING"]),
  priority: z.enum(["A", "B", "C", "D"]),
  impact: z.enum(["High", "Medium", "Low"]),
  mandatory: z.boolean(),
  unresolvedWaiting: z.boolean().default(false),
  evidence: evidenceSchema,
  workType: z.enum(["explicit", "virtual"]).default("explicit"),
  virtualWork: z.object({
    projectId: id,
    ordinal: z.number().int().positive(),
    chunkCount: z.number().int().positive(),
    estimateConfidence: z.enum(["Low", "Medium", "High"]),
    projectEvidence: evidenceSchema,
  }).strict().nullable().default(null),
}).strict().superRefine((task, context) => {
  if (task.workType === "virtual") {
    if (task.virtualWork === null) {
      context.addIssue({ code: "custom", message: "virtual work requires virtual-work evidence",
        path: ["virtualWork"] });
      return;
    }
    if (task.projectId === null || task.projectId !== task.virtualWork.projectId) {
      context.addIssue({ code: "custom", message: "virtual work must belong to its evidence project",
        path: ["projectId"] });
    }
    if (task.virtualWork.ordinal > task.virtualWork.chunkCount) {
      context.addIssue({ code: "custom", message: "virtual-work ordinal exceeds chunk count",
        path: ["virtualWork", "ordinal"] });
    }
    if (task.fixedStart !== null || task.prerequisiteIds.length > 0 || !task.mandatory) {
      context.addIssue({ code: "custom",
        message: "virtual work must be mandatory, flexible, and dependency-free" });
    }
  } else if (task.virtualWork !== null) {
    context.addIssue({ code: "custom", message: "explicit work cannot carry virtual-work evidence",
      path: ["virtualWork"] });
  }
});

export const projectSchema = z.object({
  id,
  deadline: minute.nullable(),
  safetyBufferMinutes: z.number().int().nonnegative().nullable(),
  evidence: evidenceSchema,
  definitionStatus: z.enum(["INCOMPLETE", "COARSE", "DETAILED"]),
  commitment: z.enum(["COMMITTED", "UNCOMMITTED"]),
  projectEffortMinutes: duration.nullable(),
  explicitEffortMinutes: z.number().int().nonnegative(),
  remainingExplicitEffortMinutes: z.number().int().nonnegative(),
  virtualEffortMinutes: z.number().int().nonnegative(),
  defaultWorkMode: z.string().min(1).nullable(),
  planningChunkMinutes: duration.nullable(),
  estimateConfidence: z.enum(["Low", "Medium", "High"]).nullable(),
  diagnostics: z.array(evidenceSchema),
}).strict().superRefine((project, context) => {
  const aligned = (value: number | null) => value === null || value % 15 === 0;
  if (!aligned(project.projectEffortMinutes) || !aligned(project.explicitEffortMinutes)
      || !aligned(project.remainingExplicitEffortMinutes)
      || !aligned(project.virtualEffortMinutes) || !aligned(project.planningChunkMinutes)) {
    context.addIssue({ code: "custom", message: "project effort values must align to 15 minutes" });
  }
  if (project.definitionStatus !== "INCOMPLETE") {
    if (project.deadline === null || project.projectEffortMinutes === null) {
      context.addIssue({ code: "custom",
        message: "definition-ready projects require deadline and project effort" });
    }
    if (project.explicitEffortMinutes > project.projectEffortMinutes!) {
      context.addIssue({ code: "custom", message: "explicit effort exceeds project effort" });
    }
  }
  if (project.definitionStatus === "COARSE") {
    if (project.virtualEffortMinutes <= 0 || project.defaultWorkMode === null
        || project.planningChunkMinutes === null || project.estimateConfidence === null) {
      context.addIssue({ code: "custom",
        message: "coarse projects require positive virtual effort and complete coarse metadata" });
    }
  }
  if (project.definitionStatus === "DETAILED" && project.virtualEffortMinutes !== 0) {
    context.addIssue({ code: "custom", message: "detailed projects cannot contain virtual effort" });
  }
});

export const sleepSchema = z.object({
  id,
  envelopeStart: minute,
  envelopeEnd: minute,
  minimumMinutes: duration,
  evidence: evidenceSchema,
}).refine(
  (value) => value.envelopeEnd - value.envelopeStart >= value.minimumMinutes,
  { message: "sleep minimum must fit inside its envelope" },
);

export const reserveSchema = z.object({
  id,
  envelopeStart: minute,
  envelopeEnd: minute,
  minimumMinutes: duration,
  modes: z.array(z.string().min(1)).optional(),
  evidence: evidenceSchema,
}).refine(
  (value) => value.envelopeEnd - value.envelopeStart >= value.minimumMinutes,
  { message: "reserve block must fit inside its envelope" },
);

export const intentionSchema = z.object({
  id,
  name: z.string().min(1),
  minimumMinutes: z.number().int().nonnegative().nullable(),
  targetMinutes: z.number().int().nonnegative().nullable(),
  maximumMinutes: z.number().int().nonnegative().nullable(),
  actualMinutes: z.number().int().nonnegative(),
  windowStart: minute,
  windowEnd: minute,
  matchedTaskIds: z.array(id),
  matchEvidence: z.array(evidenceSchema),
}).strict().superRefine((value, context) => {
  if (value.windowEnd <= value.windowStart) {
    context.addIssue({ code: "custom", message: "intention window end must follow start" });
  }
  if (value.minimumMinutes !== null && value.maximumMinutes !== null
      && value.minimumMinutes > value.maximumMinutes) {
    context.addIssue({ code: "custom", message: "intention minimum exceeds maximum" });
  }
  if (value.targetMinutes !== null && value.minimumMinutes !== null
      && value.targetMinutes < value.minimumMinutes) {
    context.addIssue({ code: "custom", message: "intention target is below minimum" });
  }
  if (value.targetMinutes !== null && value.maximumMinutes !== null
      && value.targetMinutes > value.maximumMinutes) {
    context.addIssue({ code: "custom", message: "intention target exceeds maximum" });
  }
});

export const scenarioSchema = z.object({
  id,
  reservations: z.array(intervalSchema),
  unlockedCommitmentIds: z.array(id),
  estimateChanges: z.array(z.object({ taskId: id, durationMinutes: duration })),
  estimateMultipliers: z.array(z.object({
    taskId: id,
    percentage: z.number().nonnegative(),
  })).optional(),
  intentionChanges: z.array(z.object({
    intentionId: id,
    minimumMinutes: z.number().int().nonnegative().nullable().optional(),
    targetMinutes: z.number().int().nonnegative().nullable().optional(),
    maximumMinutes: z.number().int().nonnegative().nullable().optional(),
  })),
  projectChanges: z.array(z.object({
    projectId: id,
    projectEffortMinutes: duration.optional(),
    deadline: minute.optional(),
    commitment: z.enum(["COMMITTED", "UNCOMMITTED"]).optional(),
    defaultWorkMode: z.string().min(1).optional(),
    planningChunkMinutes: duration.optional(),
    estimateConfidence: z.enum(["Low", "Medium", "High"]).optional(),
  }).strict().refine((change) => Object.keys(change).length > 1,
    { message: "project change must change at least one field" })).optional(),
});

export const stressProfileSchema = z.object({
  id,
  description: z.string().min(1),
  scenario: scenarioSchema,
});

const queryScope = z.enum(["baseline", "scenario"]);
const assurance = z.enum(["deadline-only", "safe"]);

const taskDemandSchema = z.object({
  kind: z.literal("TASK"),
  taskId: id,
}).strict();

const projectCapacityDemandSchema = z.object({
  kind: z.literal("PROJECT_CAPACITY"),
  projectId: id,
}).strict();

const candidateDemandSchema = z.discriminatedUnion("kind", [
  taskDemandSchema,
  projectCapacityDemandSchema,
]);

export const candidateRequestSchema = z.object({
  candidateId: id,
  revision: z.number().int().nonnegative(),
  capturedInputFingerprint: id,
  exactPlacements: z.array(z.object({
    taskId: id,
    start: minute,
  }).strict()),
  exclusions: z.array(candidateDemandSchema),
  estimateOverrides: z.array(z.discriminatedUnion("kind", [
    z.object({ kind: z.literal("TASK"), taskId: id, durationMinutes: duration }).strict(),
    z.object({
      kind: z.literal("PROJECT_CAPACITY"), projectId: id, durationMinutes: duration,
    }).strict(),
  ])),
  currentPlanSeeds: z.array(z.discriminatedUnion("kind", [
    z.object({ kind: z.literal("TASK"), taskId: id, start: minute, end: minute }).strict(),
    z.object({
      kind: z.literal("PROJECT_CAPACITY"), projectId: id, start: minute, end: minute,
    }).strict(),
  ])),
}).strict();

const maximumDeadlineOnlyQuerySchema = z.object({
  id,
  kind: z.literal("maximum-deadline-only-discretionary-duration"),
  scope: queryScope,
  start: minute,
  maximumEnd: minute,
});

const maximumSafeQuerySchema = z.object({
  id,
  kind: z.literal("maximum-safe-discretionary-duration"),
  scope: queryScope,
  start: minute,
  maximumEnd: minute,
});

const minimumRequiredWorkQuerySchema = z.object({
  id,
  kind: z.literal("minimum-required-work-in-window"),
  scope: queryScope,
  start: minute,
  end: minute,
  assurance,
});

const latestSafeStartQuerySchema = z.object({
  id,
  kind: z.literal("latest-safe-discretionary-start"),
  scope: queryScope,
  durationMinutes: duration,
  earliestStart: minute,
  latestEnd: minute,
});

const minimalUnlockSetQuerySchema = z.object({
  id,
  kind: z.literal("minimal-commitment-unlock-set"),
  scope: queryScope,
  candidateCommitmentIds: z.array(id),
  assurance,
});

const maximumProjectEffortQuerySchema = z.object({
  id,
  kind: z.literal("maximum-project-effort"),
  scope: queryScope,
  projectId: id,
  maximumEffortMinutes: duration,
  assurance,
});

const minimumProjectWorkQuerySchema = z.object({
  id,
  kind: z.literal("minimum-project-work-in-window"),
  scope: queryScope,
  projectId: id,
  start: minute,
  end: minute,
  assurance,
});

const latestProjectStartQuerySchema = z.object({
  id,
  kind: z.literal("latest-safe-project-start"),
  scope: queryScope,
  projectId: id,
  earliestStart: minute,
  latestStart: minute,
});

const earliestProjectDeadlineQuerySchema = z.object({
  id,
  kind: z.literal("earliest-feasible-project-deadline"),
  scope: queryScope,
  projectId: id,
  earliestDeadline: minute,
  latestDeadline: minute,
  assurance,
});

const minimalProjectDeferSetQuerySchema = z.object({
  id,
  kind: z.literal("minimal-project-defer-set"),
  scope: queryScope,
  candidateProjectIds: z.array(id),
  assurance,
});

export const negotiationQuerySchema = z.discriminatedUnion("kind", [
  maximumDeadlineOnlyQuerySchema,
  maximumSafeQuerySchema,
  minimumRequiredWorkQuerySchema,
  latestSafeStartQuerySchema,
  minimalUnlockSetQuerySchema,
  maximumProjectEffortQuerySchema,
  minimumProjectWorkQuerySchema,
  latestProjectStartQuerySchema,
  earliestProjectDeadlineQuerySchema,
  minimalProjectDeferSetQuerySchema,
]);

export const planningRequestSchema = z.object({
  protocolVersion: z.literal(PROTOCOL_VERSION),
  requestId: id,
  horizon: z.object({ start: minute, end: minute }).refine(
    (value) => value.end > value.start,
    { message: "horizon end must be after start" },
  ),
  schedulingQuantumMinutes: z.literal(15),
  timeoutMs: z.number().int().nonnegative().max(300_000),
  calendarCoverageEnd: minute,
  availabilityCoverageEnd: minute,
  defaultSafetyBufferMinutes: z.number().int().nonnegative(),
  hardIssues: z.array(z.string().min(1)),
  safetyIssues: z.array(z.string().min(1)),
  inputAssumptions: z.array(z.string().min(1)),
  tasks: z.array(taskSchema),
  projects: z.array(projectSchema),
  availability: z.array(intervalSchema),
  busy: z.array(intervalSchema),
  sleep: z.array(sleepSchema),
  reserve: z.array(reserveSchema),
  intentions: z.array(intentionSchema),
  stressProfiles: z.array(stressProfileSchema),
  scenario: scenarioSchema.nullable(),
  candidate: candidateRequestSchema.nullable(),
  negotiationQueries: z.array(negotiationQuerySchema).default([]),
}).superRefine((value, context) => {
  const unique = (values: string[], path: (string | number)[]) => {
    if (new Set(values).size !== values.length) {
      context.addIssue({ code: "custom", message: "IDs must be unique", path });
    }
  };
  unique(value.tasks.map((item) => item.id), ["tasks"]);
  unique(value.projects.map((item) => item.id), ["projects"]);
  unique(value.availability.map((item) => item.id), ["availability"]);
  unique(value.busy.map((item) => item.id), ["busy"]);
  unique(value.sleep.map((item) => item.id), ["sleep"]);
  unique(value.reserve.map((item) => item.id), ["reserve"]);
  unique(value.intentions.map((item) => item.id), ["intentions"]);
  unique(value.stressProfiles.map((item) => item.id), ["stressProfiles"]);
  unique([
    ...(value.scenario === null ? [] : [value.scenario.id]),
    ...value.stressProfiles.map((item) => item.scenario.id),
  ], ["scenarioIds"]);
  unique(value.negotiationQueries.map((item) => item.id), ["negotiationQueries"]);
  const taskIds = new Set(value.tasks.map((item) => item.id));
  const projectIds = new Set(value.projects.map((item) => item.id));
  const intentionIds = new Set(value.intentions.map((item) => item.id));
  const addMissing = (message: string, path: (string | number)[]) =>
    context.addIssue({ code: "custom", message, path });
  value.tasks.forEach((task, index) => {
    if (task.projectId !== null && !projectIds.has(task.projectId)) {
      addMissing("task references an unknown project", ["tasks", index, "projectId"]);
    }
    unique(task.prerequisiteIds, ["tasks", index, "prerequisiteIds"]);
    task.prerequisiteIds.forEach((reference, referenceIndex) => {
      if (!taskIds.has(reference) || reference === task.id) {
        addMissing("task prerequisite must reference another task",
          ["tasks", index, "prerequisiteIds", referenceIndex]);
      }
    });
  });
  value.projects.forEach((project, projectIndex) => {
    const virtual = value.tasks.filter((task) => task.workType === "virtual"
      && task.projectId === project.id).sort((left, right) =>
      left.virtualWork!.ordinal - right.virtualWork!.ordinal);
    const virtualMinutes = virtual.reduce((sum, task) => sum + (task.durationMinutes ?? 0), 0);
    if (project.definitionStatus === "COARSE" && virtualMinutes !== project.virtualEffortMinutes) {
      addMissing("virtual chunks must exactly represent project virtual effort",
        ["projects", projectIndex, "virtualEffortMinutes"]);
    }
    if (project.definitionStatus !== "COARSE" && virtual.length > 0) {
      addMissing("only definition-ready coarse projects may provide virtual chunks",
        ["projects", projectIndex, "definitionStatus"]);
    }
    virtual.forEach((task, index) => {
      const expectedDuration = project.planningChunkMinutes === null ? null : Math.min(
        project.planningChunkMinutes,
        project.virtualEffortMinutes - index * project.planningChunkMinutes,
      );
      if (task.id !== `${project.id}:virtual:${index + 1}`
          || task.virtualWork?.ordinal !== index + 1
          || task.virtualWork.chunkCount !== virtual.length
          || task.durationMinutes !== expectedDuration
          || task.deadline !== project.deadline
          || task.deadlineSource !== "project"
          || task.workMode !== project.defaultWorkMode
          || task.virtualWork.estimateConfidence !== project.estimateConfidence
          || task.evidence.sourceId !== project.evidence.sourceId
          || task.evidence.kind !== project.evidence.kind
          || task.evidence.detail !== project.evidence.detail
          || task.virtualWork.projectEvidence.sourceId !== project.evidence.sourceId
          || task.virtualWork.projectEvidence.kind !== project.evidence.kind
          || task.virtualWork.projectEvidence.detail !== project.evidence.detail) {
        addMissing("virtual chunks must deterministically inherit project definition evidence",
          ["tasks", value.tasks.indexOf(task)]);
      }
    });
  });
  value.intentions.forEach((intention, index) => {
    unique(intention.matchedTaskIds, ["intentions", index, "matchedTaskIds"]);
    intention.matchedTaskIds.forEach((reference, referenceIndex) => {
      if (!taskIds.has(reference)) {
        addMissing("intention references an unknown task",
          ["intentions", index, "matchedTaskIds", referenceIndex]);
      }
    });
  });
  value.availability.forEach((interval, index) => {
    if (interval.kind !== "availability") {
      addMissing("availability intervals must have availability kind",
        ["availability", index, "kind"]);
    }
  });
  value.busy.forEach((interval, index) => {
    if (interval.kind === "availability") {
      addMissing("busy intervals cannot have availability kind", ["busy", index, "kind"]);
    }
  });

  const validateScenario = (
    scenario: Scenario,
    path: (string | number)[],
    existingReservationIds: Set<string>,
  ) => {
    unique(scenario.reservations.map((item) => item.id), [...path, "reservations"]);
    unique(scenario.unlockedCommitmentIds, [...path, "unlockedCommitmentIds"]);
    unique(scenario.estimateChanges.map((item) => item.taskId), [...path, "estimateChanges"]);
    unique((scenario.estimateMultipliers ?? []).map((item) => item.taskId),
      [...path, "estimateMultipliers"]);
    unique(scenario.intentionChanges.map((item) => item.intentionId),
      [...path, "intentionChanges"]);
    unique((scenario.projectChanges ?? []).map((item) => item.projectId),
      [...path, "projectChanges"]);
    scenario.reservations.forEach((reservation, index) => {
      if (reservation.kind !== "scenario-reservation") {
        addMissing("scenario reservations must have scenario-reservation kind",
          [...path, "reservations", index, "kind"]);
      }
      if ((reservation.end - reservation.start) % value.schedulingQuantumMinutes !== 0) {
        addMissing("scenario reservation duration must match the scheduling quantum",
          [...path, "reservations", index]);
      }
      if (reservation.start < value.horizon.start || reservation.end > value.horizon.end) {
        addMissing("scenario reservation must fit inside the planning horizon",
          [...path, "reservations", index]);
      }
      if (existingReservationIds.has(reservation.id)) {
        addMissing("scenario reservation ID duplicates an existing busy interval",
          [...path, "reservations", index, "id"]);
      }
    });
    scenario.unlockedCommitmentIds.forEach((reference, index) => {
      const task = value.tasks.find((item) => item.id === reference);
      if (!task || task.fixedStart === null) {
        addMissing("unlocked commitment must reference a fixed-start task",
          [...path, "unlockedCommitmentIds", index]);
      }
    });
    scenario.estimateChanges.forEach((change, index) => {
      if (!taskIds.has(change.taskId)) {
        addMissing("estimate change references an unknown task",
          [...path, "estimateChanges", index, "taskId"]);
      }
      if (change.durationMinutes % value.schedulingQuantumMinutes !== 0) {
        addMissing("scenario estimate duration must match the scheduling quantum",
          [...path, "estimateChanges", index, "durationMinutes"]);
      }
    });
    (scenario.estimateMultipliers ?? []).forEach((change, index) => {
      if (!taskIds.has(change.taskId)) {
        addMissing("estimate multiplier references an unknown task",
          [...path, "estimateMultipliers", index, "taskId"]);
      }
    });
    scenario.intentionChanges.forEach((change, index) => {
      const original = value.intentions.find((item) => item.id === change.intentionId);
      if (!original) {
        addMissing("intention change references an unknown intention",
          [...path, "intentionChanges", index, "intentionId"]);
        return;
      }
      const minimum = change.minimumMinutes === undefined
        ? original.minimumMinutes : change.minimumMinutes;
      const target = change.targetMinutes === undefined
        ? original.targetMinutes : change.targetMinutes;
      const maximum = change.maximumMinutes === undefined
        ? original.maximumMinutes : change.maximumMinutes;
      if (minimum !== null && maximum !== null && minimum > maximum) {
        addMissing("merged intention minimum exceeds maximum",
          [...path, "intentionChanges", index]);
      }
      if (target !== null && minimum !== null && target < minimum) {
        addMissing("merged intention target is below minimum",
          [...path, "intentionChanges", index]);
      }
      if (target !== null && maximum !== null && target > maximum) {
        addMissing("merged intention target exceeds maximum",
          [...path, "intentionChanges", index]);
      }
    });
    (scenario.projectChanges ?? []).forEach((change, index) => {
      if (!projectIds.has(change.projectId)) {
        addMissing("project change references an unknown project",
          [...path, "projectChanges", index, "projectId"]);
      }
      if (change.projectEffortMinutes !== undefined
          && change.projectEffortMinutes % value.schedulingQuantumMinutes !== 0) {
        addMissing("project effort must match the scheduling quantum",
          [...path, "projectChanges", index, "projectEffortMinutes"]);
      }
      if (change.planningChunkMinutes !== undefined
          && change.planningChunkMinutes % value.schedulingQuantumMinutes !== 0) {
        addMissing("planning chunk must match the scheduling quantum",
          [...path, "projectChanges", index, "planningChunkMinutes"]);
      }
    });
  };
  const busyIds = new Set(value.busy.map((item) => item.id));
  if (value.scenario !== null) validateScenario(value.scenario, ["scenario"], busyIds);
  value.stressProfiles.forEach((profile, index) =>
    validateScenario(profile.scenario, ["stressProfiles", index, "scenario"], busyIds));

  value.negotiationQueries.forEach((query, index) => {
    const bounds = query.kind === "minimum-required-work-in-window"
      ? [query.start, query.end]
      : query.kind === "minimum-project-work-in-window"
        ? [query.start, query.end]
      : query.kind === "latest-safe-discretionary-start"
        ? [query.earliestStart, query.latestEnd]
        : query.kind === "latest-safe-project-start"
          ? [query.earliestStart, query.latestStart + value.schedulingQuantumMinutes]
        : query.kind === "earliest-feasible-project-deadline"
          ? [query.earliestDeadline - value.schedulingQuantumMinutes, query.latestDeadline]
        : query.kind === "minimal-commitment-unlock-set"
            || query.kind === "minimal-project-defer-set"
            || query.kind === "maximum-project-effort"
          ? null
          : [query.start, query.maximumEnd];
    if (bounds !== null && (bounds[1]! <= bounds[0]!
        || bounds[0]! < value.horizon.start || bounds[1]! > value.horizon.end)) {
      context.addIssue({
        code: "custom",
        message: "query interval must be nonempty and fit inside the planning horizon",
        path: ["negotiationQueries", index],
      });
    }
    if (query.scope === "scenario" && value.scenario === null) {
      context.addIssue({
        code: "custom",
        message: "scenario query requires a scenario",
        path: ["negotiationQueries", index, "scope"],
      });
    }
    if (query.kind === "latest-safe-discretionary-start"
        && query.durationMinutes % value.schedulingQuantumMinutes !== 0) {
      addMissing("query duration must match the scheduling quantum",
        ["negotiationQueries", index, "durationMinutes"]);
    }
    if (query.kind === "minimal-commitment-unlock-set") {
      unique(query.candidateCommitmentIds,
        ["negotiationQueries", index, "candidateCommitmentIds"]);
      query.candidateCommitmentIds.forEach((reference, referenceIndex) => {
        const task = value.tasks.find((item) => item.id === reference);
        if (!task || task.fixedStart === null) {
          addMissing("unlock candidate must reference a fixed-start task",
            ["negotiationQueries", index, "candidateCommitmentIds", referenceIndex]);
        }
      });
    }
    if ("projectId" in query && !projectIds.has(query.projectId)) {
      addMissing("query references an unknown project",
        ["negotiationQueries", index, "projectId"]);
    }
    if (query.kind === "maximum-project-effort"
        && query.maximumEffortMinutes % value.schedulingQuantumMinutes !== 0) {
      addMissing("maximum project effort must match the scheduling quantum",
        ["negotiationQueries", index, "maximumEffortMinutes"]);
    }
    if (query.kind === "minimal-project-defer-set") {
      unique(query.candidateProjectIds,
        ["negotiationQueries", index, "candidateProjectIds"]);
      query.candidateProjectIds.forEach((reference, referenceIndex) => {
        if (!projectIds.has(reference)) {
          addMissing("defer candidate must reference a project",
            ["negotiationQueries", index, "candidateProjectIds", referenceIndex]);
        }
      });
    }
  });

  if (value.candidate !== null) {
    const candidate = value.candidate;
    const demandKey = (demand: z.infer<typeof candidateDemandSchema>) => demand.kind === "TASK"
      ? `TASK:${demand.taskId}` : `PROJECT_CAPACITY:${demand.projectId}`;
    unique(candidate.exactPlacements.map((placement) => placement.taskId),
      ["candidate", "exactPlacements"]);
    unique(candidate.exclusions.map(demandKey), ["candidate", "exclusions"]);
    unique(candidate.estimateOverrides.map(demandKey), ["candidate", "estimateOverrides"]);
    unique(candidate.currentPlanSeeds.filter((seed) => seed.kind === "TASK")
      .map((seed) => seed.taskId), ["candidate", "currentPlanSeeds"]);
    const excluded = new Set(candidate.exclusions.map(demandKey));
    const overridden = new Set(candidate.estimateOverrides.map(demandKey));
    const taskOverrideMinutes = new Map(candidate.estimateOverrides.flatMap((override) =>
      override.kind === "TASK" ? [[override.taskId, override.durationMinutes] as const] : []));
    const capacityOverrideMinutes = new Map(candidate.estimateOverrides.flatMap((override) =>
      override.kind === "PROJECT_CAPACITY"
        ? [[override.projectId, override.durationMinutes] as const] : []));
    candidate.exactPlacements.forEach((placement, index) => {
      const task = value.tasks.find((item) => item.id === placement.taskId);
      if (!task || task.workType !== "explicit" || task.fixedStart !== null) {
        addMissing("exact placement must reference a flexible explicit task",
          ["candidate", "exactPlacements", index, "taskId"]);
      }
      if (!isAligned(placement.start, value.schedulingQuantumMinutes)) {
        addMissing("exact placement start must match the scheduling quantum",
          ["candidate", "exactPlacements", index, "start"]);
      }
      const placedDuration = task === undefined ? null
        : taskOverrideMinutes.get(task.id) ?? task.durationMinutes;
      if (placedDuration !== null && placement.start + placedDuration > value.horizon.end) {
        addMissing("exact placement must fit inside the replacement horizon",
          ["candidate", "exactPlacements", index, "start"]);
      }
      if (excluded.has(`TASK:${placement.taskId}`)) {
        addMissing("excluded task cannot also have an exact placement",
          ["candidate", "exactPlacements", index, "taskId"]);
      }
    });
    candidate.exclusions.forEach((demand, index) => {
      if (!candidateDemandExists(value, demand)) {
        addMissing("candidate exclusion references unknown or incompatible demand",
          ["candidate", "exclusions", index]);
      }
    });
    candidate.estimateOverrides.forEach((override, index) => {
      if (!candidateDemandExists(value, override)) {
        addMissing("candidate estimate override references unknown or incompatible demand",
          ["candidate", "estimateOverrides", index]);
      }
      if (!isAligned(override.durationMinutes, value.schedulingQuantumMinutes)) {
        addMissing("candidate estimate override must match the scheduling quantum",
          ["candidate", "estimateOverrides", index, "durationMinutes"]);
      }
      if (excluded.has(demandKey(override))) {
        addMissing("excluded demand cannot also have an estimate override",
          ["candidate", "estimateOverrides", index]);
      }
    });
    candidate.currentPlanSeeds.forEach((seed, index) => {
      if (!candidateDemandExists(value, seed)) {
        addMissing("current-plan seed references unknown or incompatible demand",
          ["candidate", "currentPlanSeeds", index]);
      }
      if (seed.end <= seed.start || !isAligned(seed.start, value.schedulingQuantumMinutes)
          || !isAligned(seed.end, value.schedulingQuantumMinutes)) {
        addMissing("current-plan seed must be a positive aligned interval",
          ["candidate", "currentPlanSeeds", index]);
      }
      if (seed.start < value.horizon.start || seed.end > value.horizon.end) {
        addMissing("current-plan seed must fit inside the replacement horizon",
          ["candidate", "currentPlanSeeds", index]);
      }
      if (excluded.has(demandKey(seed))) {
        addMissing("excluded demand cannot also seed the candidate",
          ["candidate", "currentPlanSeeds", index]);
      }
      if (seed.kind === "TASK") {
        const task = value.tasks.find((item) => item.id === seed.taskId);
        const expectedDuration = task === undefined ? null
          : taskOverrideMinutes.get(task.id) ?? task.durationMinutes;
        if (task?.fixedStart !== null || expectedDuration === null
            || seed.end - seed.start !== expectedDuration) {
          addMissing("task seed must match one flexible task's candidate duration",
            ["candidate", "currentPlanSeeds", index]);
        }
      }
    });
    const capacitySeeds = new Map<string, { start: number; end: number; index: number }[]>();
    candidate.currentPlanSeeds.forEach((seed, index) => {
      if (seed.kind !== "PROJECT_CAPACITY") return;
      const seeds = capacitySeeds.get(seed.projectId) ?? [];
      seeds.push({ start: seed.start, end: seed.end, index });
      capacitySeeds.set(seed.projectId, seeds);
    });
    capacitySeeds.forEach((seeds, projectId) => {
      const project = value.projects.find((item) => item.id === projectId)!;
      const total = capacityOverrideMinutes.get(projectId) ?? project.virtualEffortMinutes;
      const chunk = project.planningChunkMinutes!;
      const expectedDurations = Array.from({ length: Math.ceil(total / chunk) }, (_, index) =>
        Math.min(chunk, total - index * chunk));
      seeds.sort((left, right) => left.start - right.start || left.end - right.end);
      seeds.forEach((seed, index) => {
        if (seed.end - seed.start !== expectedDurations[index]) {
          addMissing("capacity seeds must deterministically match candidate virtual chunks",
            ["candidate", "currentPlanSeeds", seed.index]);
        }
      });
    });
    for (const key of overridden) {
      if (excluded.has(key)) {
        addMissing("excluded demand cannot also have an estimate override", ["candidate"]);
      }
    }
  }
});

function isAligned(value: number, quantum: number) {
  return value % quantum === 0;
}

function candidateDemandExists(
  request: Pick<z.infer<typeof planningRequestSchema>, "tasks" | "projects">,
  demand: z.infer<typeof candidateDemandSchema>,
) {
  if (demand.kind === "TASK") {
    return request.tasks.some((task) => task.id === demand.taskId && task.workType === "explicit");
  }
  return request.projects.some((project) => project.id === demand.projectId
    && project.definitionStatus === "COARSE");
}

export type PlanningRequest = z.infer<typeof planningRequestSchema>;
export type Scenario = z.input<typeof scenarioSchema>;
export type Task = z.infer<typeof taskSchema>;
export type NegotiationQuery = z.infer<typeof negotiationQuerySchema>;
export type CandidateRequest = z.infer<typeof candidateRequestSchema>;

export const placementSchema = z.object({
  taskId: id,
  projectId: id.nullable(),
  demandKind: z.enum(["TASK", "PROJECT_CAPACITY"]),
  sourceId: id,
  start: minute,
  end: minute,
  kind: z.enum(["fixed", "proposed"]),
  rationale: z.enum([
    "fixed-commitment",
    "exact-user-placement",
    "current-plan-seed-kept",
    "current-plan-seed-moved",
    "solver-selected",
  ]),
  estimateConfidence: z.enum(["Low", "Medium", "High"]).nullable(),
});

const candidateIdentitySchema = z.object({
  candidateId: id,
  revision: z.number().int().nonnegative(),
  capturedInputFingerprint: id,
  normalizedRequestId: id,
}).strict();

const omissionSchema = z.object({
  demandKind: z.enum(["TASK", "PROJECT_CAPACITY"]),
  sourceId: id,
  taskId: id.nullable(),
  projectId: id.nullable(),
  durationMinutes: z.number().int().nonnegative().nullable(),
  rationale: z.enum(["user-excluded", "solver-omitted", "unresolved-input"]),
  deadline: minute.nullable(),
  estimateConfidence: z.enum(["Low", "Medium", "High"]).nullable(),
}).strict();

const candidateEvidenceSchema = z.object({
  identity: candidateIdentitySchema,
  exactPlacementTaskIds: z.array(id),
  excludedSourceIds: z.array(id),
  estimateOverrideSourceIds: z.array(id),
  seed: z.object({
    totalCount: z.number().int().nonnegative(),
    keptCount: z.number().int().nonnegative(),
    movedCount: z.number().int().nonnegative(),
    omittedCount: z.number().int().nonnegative(),
    keptSourceIds: z.array(id),
    movedSourceIds: z.array(id),
    omittedSourceIds: z.array(id),
  }).strict(),
  deadlineStatus: z.enum(["SATISFIED", "CONFLICT", "UNKNOWN"]),
  safetyStatus: z.enum(["SATISFIED", "AT_RISK", "UNKNOWN"]),
  intentionStatus: z.enum(["SATISFIED", "AT_RISK", "UNKNOWN"]),
  estimateConfidenceStatus: z.enum(["HIGH", "MEDIUM", "LOW", "UNKNOWN"]),
  capacityStatus: z.enum(["SATISFIED", "AT_RISK", "UNKNOWN"]),
  placedCapacityMinutes: z.number().int().nonnegative(),
  omittedCapacityMinutes: z.number().int().nonnegative(),
}).strict();

const feasibility = z.enum(["PROVEN FEASIBLE", "PROVEN INFEASIBLE", "UNKNOWN"]);

const relaxationSchema = z.object({
  type: z.enum([
    "unlock-commitment",
    "add-compatible-availability",
    "provide-duration-estimate",
    "model-release-condition",
    "adjust-safety-policy",
    "resolve-input-assumption",
    "move-after-release",
  ]),
  text: z.string().min(1),
});

export const solveResultSchema = z.object({
  feasibility,
  safety: z.enum(["SAFE", "TIGHT"]).nullable(),
  resilience: z.enum(["RESILIENT", "FRAGILE"]).nullable(),
  placements: z.array(placementSchema),
  reservePlacements: z.array(z.object({ id, start: minute, end: minute })),
  sleepPlacements: z.array(z.object({ id, start: minute, end: minute })),
  intentions: z.array(z.object({
    id,
    allocatedMinutes: z.number().int().nonnegative(),
    minimumShortfallMinutes: z.number().int().nonnegative(),
    targetDeviationMinutes: z.number().int().nonnegative(),
    maximumExcessMinutes: z.number().int().nonnegative(),
  })),
  deadlineMargins: z.array(z.object({
    taskId: id,
    projectId: id.nullable(),
    deadline: minute,
    completionTime: minute,
    hardDeadlineMarginMinutes: z.number().int(),
    safetyBufferMinutes: z.number().int().nonnegative(),
    safetyMarginMinutes: z.number().int(),
  })).default([]),
  omissions: z.array(omissionSchema).default([]),
  candidateEvidence: candidateEvidenceSchema.nullable().default(null),
  conflicts: z.array(z.object({
    constraintId: id,
    sourceId: id,
    kind: z.string().min(1),
    message: z.string().min(1),
    taskIds: z.array(id),
    projectIds: z.array(id),
    shared: z.boolean(),
    relaxation: relaxationSchema.optional(),
  })),
  assumptions: z.array(z.string()),
  unlockedCommitmentIds: z.array(id),
  stressResults: z.array(z.object({
    id,
    feasibility,
  })),
});

const projectResultSchema = z.object({
  projectId: id,
  definitionStatus: z.enum(["INCOMPLETE", "COARSE", "DETAILED"]),
  commitment: z.enum(["COMMITTED", "UNCOMMITTED"]),
  isolatedFeasibility: z.enum(["FEASIBLE", "INFEASIBLE", "UNKNOWN", "UNCOMMITTED"]),
  proofKind: z.enum(["CAPACITY FEASIBLE", "STRUCTURALLY FEASIBLE"]).nullable(),
  isolatedResult: solveResultSchema.nullable(),
  borrowedPrerequisiteTaskIds: z.array(id),
  borrowedPrerequisiteProjectIds: z.array(id),
  portfolioStatus: z.enum(["FITS", "TIGHT", "CONFLICT-INVOLVED", "UNKNOWN", "UNCOMMITTED"]),
  hardDeadlineMarginMinutes: z.number().int().nullable(),
  safetyMarginMinutes: z.number().int().nullable(),
  conflictTaskIds: z.array(id),
  conflictProjectIds: z.array(id),
}).strict();

const portfolioResultSchema = z.object({
  definitionStatus: z.enum(["COMPLETE", "INCOMPLETE"]),
  feasibility,
  safety: z.enum(["SAFE", "TIGHT"]).nullable(),
  modeledProjectIds: z.array(id),
  excludedProjectIds: z.array(id),
  modeledSubset: z.boolean(),
  globalResult: solveResultSchema,
  projectResults: z.array(projectResultSchema),
}).strict();

export const planningResponseSchema = z.object({
  protocolVersion: z.literal(PROTOCOL_VERSION),
  solverVersion: z.literal(SOLVER_VERSION),
  requestId: id,
  candidateIdentity: candidateIdentitySchema.nullable(),
  status: z.enum(["ok", "invalid-request", "internal-error"]),
  baseline: solveResultSchema.nullable(),
  scenario: solveResultSchema.nullable(),
  baselinePortfolio: portfolioResultSchema.nullable(),
  scenarioPortfolio: portfolioResultSchema.nullable(),
  comparison: z.object({
    interpretation: z.string(),
    movedTaskIds: z.array(id),
    addedTaskIds: z.array(id).default([]),
    droppedTaskIds: z.array(id).default([]),
    safetyTransition: z.object({
      baseline: z.enum(["SAFE", "TIGHT"]).nullable(),
      scenario: z.enum(["SAFE", "TIGHT"]).nullable(),
    }).default({ baseline: null, scenario: null }),
    resilienceTransition: z.object({
      baseline: z.enum(["RESILIENT", "FRAGILE"]).nullable(),
      scenario: z.enum(["RESILIENT", "FRAGILE"]).nullable(),
    }).default({ baseline: null, scenario: null }),
    taskStartDeltas: z.array(z.object({
      taskId: id,
      baselineStart: minute,
      scenarioStart: minute,
      deltaMinutes: z.number().int(),
    })).default([]),
    intentionAllocationDeltas: z.array(z.object({
      intentionId: id,
      baselineAllocatedMinutes: z.number().int().nonnegative(),
      scenarioAllocatedMinutes: z.number().int().nonnegative(),
      deltaMinutes: z.number().int(),
    })).default([]),
    reservePlacementDelta: z.object({
      baselineCount: z.number().int().nonnegative(),
      scenarioCount: z.number().int().nonnegative(),
      countDelta: z.number().int(),
      baselineMinutes: z.number().int().nonnegative(),
      scenarioMinutes: z.number().int().nonnegative(),
      minutesDelta: z.number().int(),
    }).default({
      baselineCount: 0,
      scenarioCount: 0,
      countDelta: 0,
      baselineMinutes: 0,
      scenarioMinutes: 0,
      minutesDelta: 0,
    }),
    stressFeasibilityTransitions: z.array(z.object({
      id,
      baseline: feasibility.nullable(),
      scenario: feasibility.nullable(),
    })).default([]),
    projectDeltas: z.array(z.object({
      projectId: id,
      baselineDefinitionStatus: z.enum(["INCOMPLETE", "COARSE", "DETAILED"]),
      scenarioDefinitionStatus: z.enum(["INCOMPLETE", "COARSE", "DETAILED"]),
      baselineEffortMinutes: z.number().int().positive().nullable(),
      scenarioEffortMinutes: z.number().int().positive().nullable(),
      effortDeltaMinutes: z.number().int().nullable(),
      baselineDeadline: minute.nullable(),
      scenarioDeadline: minute.nullable(),
      baselineCommitment: z.enum(["COMMITTED", "UNCOMMITTED"]),
      scenarioCommitment: z.enum(["COMMITTED", "UNCOMMITTED"]),
      baselineIsolatedFeasibility: z.enum(["FEASIBLE", "INFEASIBLE", "UNKNOWN", "UNCOMMITTED"]),
      scenarioIsolatedFeasibility: z.enum(["FEASIBLE", "INFEASIBLE", "UNKNOWN", "UNCOMMITTED"]),
      baselinePortfolioStatus: z.enum(["FITS", "TIGHT", "CONFLICT-INVOLVED", "UNKNOWN", "UNCOMMITTED"]),
      scenarioPortfolioStatus: z.enum(["FITS", "TIGHT", "CONFLICT-INVOLVED", "UNKNOWN", "UNCOMMITTED"]),
    })).default([]),
  }).nullable(),
  negotiationResults: z.array(z.discriminatedUnion("kind", [z.object({
    id,
    kind: z.literal("maximum-deadline-only-discretionary-duration"),
    scope: queryScope,
    feasibility: z.enum(["PROVEN FEASIBLE", "PROVEN INFEASIBLE", "UNKNOWN"]),
    maximumDurationMinutes: z.number().int().nonnegative().nullable(),
    testedStart: minute,
    testedMaximumEnd: minute,
    assumptions: z.array(z.string()),
  }), z.object({
    id,
    kind: z.literal("maximum-safe-discretionary-duration"),
    scope: queryScope,
    feasibility: z.enum(["PROVEN FEASIBLE", "PROVEN INFEASIBLE", "UNKNOWN"]),
    maximumDurationMinutes: z.number().int().nonnegative().nullable(),
    testedStart: minute,
    testedMaximumEnd: minute,
    assumptions: z.array(z.string()),
  }), z.object({
    id,
    kind: z.literal("minimum-required-work-in-window"),
    scope: queryScope,
    assurance,
    feasibility: z.enum(["PROVEN FEASIBLE", "PROVEN INFEASIBLE", "UNKNOWN"]),
    minimumRequiredMinutes: z.number().int().nonnegative().nullable(),
    testedStart: minute,
    testedEnd: minute,
    assumptions: z.array(z.string()),
  }), z.object({
    id,
    kind: z.literal("latest-safe-discretionary-start"),
    scope: queryScope,
    feasibility: z.enum(["PROVEN FEASIBLE", "PROVEN INFEASIBLE", "UNKNOWN"]),
    latestStart: minute.nullable(),
    testedDurationMinutes: duration,
    testedEarliestStart: minute,
    testedLatestEnd: minute,
    assumptions: z.array(z.string()),
  }), z.object({
    id,
    kind: z.literal("minimal-commitment-unlock-set"),
    scope: queryScope,
    assurance,
    feasibility: z.enum(["PROVEN FEASIBLE", "PROVEN INFEASIBLE", "UNKNOWN"]),
    candidateCommitmentIds: z.array(id),
    unlockedCommitmentIds: z.array(id).nullable(),
    assumptions: z.array(z.string()),
  }), z.object({
    id,
    kind: z.literal("maximum-project-effort"),
    scope: queryScope,
    projectId: id,
    assurance,
    feasibility,
    maximumEffortMinutes: z.number().int().nonnegative().nullable(),
    testedMaximumEffortMinutes: duration,
    assumptions: z.array(z.string()),
  }), z.object({
    id,
    kind: z.literal("minimum-project-work-in-window"),
    scope: queryScope,
    projectId: id,
    assurance,
    feasibility,
    minimumRequiredMinutes: z.number().int().nonnegative().nullable(),
    testedStart: minute,
    testedEnd: minute,
    assumptions: z.array(z.string()),
  }), z.object({
    id,
    kind: z.literal("latest-safe-project-start"),
    scope: queryScope,
    projectId: id,
    feasibility,
    latestStart: minute.nullable(),
    testedEarliestStart: minute,
    testedLatestStart: minute,
    assumptions: z.array(z.string()),
  }), z.object({
    id,
    kind: z.literal("earliest-feasible-project-deadline"),
    scope: queryScope,
    projectId: id,
    assurance,
    feasibility,
    earliestDeadline: minute.nullable(),
    testedEarliestDeadline: minute,
    testedLatestDeadline: minute,
    assumptions: z.array(z.string()),
  }), z.object({
    id,
    kind: z.literal("minimal-project-defer-set"),
    scope: queryScope,
    assurance,
    feasibility,
    candidateProjectIds: z.array(id),
    deferredProjectIds: z.array(id).nullable(),
    conflictProjectIds: z.array(id),
    assumptions: z.array(z.string()),
  })])).default([]),
  errors: z.array(z.object({ path: z.string(), message: z.string() })),
}).strict().superRefine((response, context) => {
  if (response.candidateIdentity !== null
      && response.candidateIdentity.normalizedRequestId !== response.requestId) {
    context.addIssue({
      code: "custom",
      message: "candidate identity must echo the response request ID",
      path: ["candidateIdentity", "normalizedRequestId"],
    });
  }
});

export type PlanningResponse = z.infer<typeof planningResponseSchema>;
export type SolveResult = z.infer<typeof solveResultSchema>;

export function responseEnvelope(
  requestId: string,
  values: Omit<PlanningResponse,
    "protocolVersion" | "solverVersion" | "requestId" | "candidateIdentity">
    & { candidateIdentity?: PlanningResponse["candidateIdentity"] },
): PlanningResponse {
  return planningResponseSchema.parse({
    protocolVersion: PROTOCOL_VERSION,
    solverVersion: SOLVER_VERSION,
    requestId,
    candidateIdentity: values.candidateIdentity ?? null,
    ...values,
  });
}
