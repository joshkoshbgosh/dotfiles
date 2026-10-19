import type { PlanningRequest, Scenario } from "./protocol.js";

export function applyScenario(
  request: PlanningRequest,
  scenario: Scenario,
): PlanningRequest {
  const estimates = new Map(
    scenario.estimateChanges.map((change) => [change.taskId, change.durationMinutes]),
  );
  const multipliers = new Map(
    (scenario.estimateMultipliers ?? []).map((change) => [change.taskId, change.percentage]),
  );
  const intentions = new Map(
    scenario.intentionChanges.map((change) => [change.intentionId, change]),
  );
  const projectChanges = new Map(
    (scenario.projectChanges ?? []).map((change) => [change.projectId, change]),
  );
  const projects = request.projects.map((project) => {
    const change = projectChanges.get(project.id);
    const changed = change === undefined ? project : {
      ...project,
      projectEffortMinutes: change.projectEffortMinutes ?? project.projectEffortMinutes,
      deadline: change.deadline ?? project.deadline,
      commitment: change.commitment ?? project.commitment,
      defaultWorkMode: change.defaultWorkMode ?? project.defaultWorkMode,
      planningChunkMinutes: change.planningChunkMinutes ?? project.planningChunkMinutes,
      estimateConfidence: change.estimateConfidence ?? project.estimateConfidence,
    };
    const virtualEffortMinutes = Math.max(
      (changed.projectEffortMinutes ?? 0) - changed.explicitEffortMinutes, 0,
    );
    const metadataReady = changed.defaultWorkMode !== null
      && changed.planningChunkMinutes !== null && changed.estimateConfidence !== null;
    return {
      ...changed,
      virtualEffortMinutes,
      definitionStatus: changed.projectEffortMinutes === null
          || changed.explicitEffortMinutes > changed.projectEffortMinutes
          || (virtualEffortMinutes > 0 && !metadataReady)
        ? "INCOMPLETE" as const
        : virtualEffortMinutes > 0 ? "COARSE" as const : "DETAILED" as const,
    };
  });
  const projectById = new Map(projects.map((project) => [project.id, project]));
  const explicitTasks = request.tasks.filter((task) => task.workType === "explicit").map((task) => {
    const project = task.projectId === null ? undefined : projectById.get(task.projectId);
    return task.deadlineSource === "project" && project !== undefined
      ? { ...task, deadline: project.deadline }
      : task;
  });
  const virtualTasks = projects.flatMap((project) => {
    if (project.definitionStatus !== "COARSE" || project.deadline === null
        || project.defaultWorkMode === null || project.planningChunkMinutes === null
        || project.estimateConfidence === null) return [];
    const chunkCount = Math.ceil(project.virtualEffortMinutes / project.planningChunkMinutes);
    return Array.from({ length: chunkCount }, (_, index) => {
      const durationMinutes = Math.min(
        project.planningChunkMinutes!,
        project.virtualEffortMinutes - index * project.planningChunkMinutes!,
      );
      return {
        id: `${project.id}:virtual:${index + 1}`,
        projectId: project.id,
        durationMinutes,
        workMode: project.defaultWorkMode!,
        deadline: project.deadline,
        deadlineSource: "project" as const,
        releaseTime: null,
        fixedStart: null,
        preferredStart: null,
        prerequisiteIds: [],
        state: "TODO" as const,
        priority: "A" as const,
        impact: "High" as const,
        mandatory: true,
        unresolvedWaiting: false,
        evidence: project.evidence,
        workType: "virtual" as const,
        virtualWork: {
          projectId: project.id,
          ordinal: index + 1,
          chunkCount,
          estimateConfidence: project.estimateConfidence!,
          projectEvidence: project.evidence,
        },
      };
    });
  });

  return {
    ...request,
    projects,
    tasks: [...explicitTasks, ...virtualTasks].map((task) => {
      const duration = estimates.get(task.id) ?? task.durationMinutes;
      const percentage = multipliers.get(task.id);
      return {
        ...task,
        durationMinutes: duration === null || percentage === undefined
          ? duration
          : Math.ceil(
            duration * (1 + percentage / 100) / request.schedulingQuantumMinutes,
          ) * request.schedulingQuantumMinutes,
      };
    }),
    busy: [...request.busy, ...scenario.reservations],
    intentions: request.intentions.map((intention) => {
      const change = intentions.get(intention.id);
      if (!change) return intention;
      return {
        ...intention,
        minimumMinutes: change.minimumMinutes !== undefined
          ? change.minimumMinutes : intention.minimumMinutes,
        targetMinutes: change.targetMinutes !== undefined
          ? change.targetMinutes : intention.targetMinutes,
        maximumMinutes: change.maximumMinutes !== undefined
          ? change.maximumMinutes : intention.maximumMinutes,
      };
    }),
    scenario: null,
  };
}
