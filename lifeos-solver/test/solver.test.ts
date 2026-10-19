import { readFile } from "node:fs/promises";

import fc from "fast-check";
import { describe, expect, test } from "vitest";

import {
  PROTOCOL_VERSION,
  SOLVER_VERSION,
  planningRequestSchema,
  planningResponseSchema,
  type PlanningRequest,
} from "../src/protocol.js";
import { applyScenario } from "../src/scenario.js";
import { solvePlanningRequest } from "../src/solver.js";
import { verifyHardConstraints, verifyPlanningResponse } from "../src/verify.js";

async function fixture(name: string): Promise<PlanningRequest> {
  const text = await readFile(new URL(`fixtures/${name}.json`, import.meta.url), "utf8");
  return planningRequestSchema.parse(JSON.parse(text));
}

async function golden(name: string): Promise<Record<string, unknown>> {
  const text = await readFile(new URL(`goldens/${name}.semantic.json`, import.meta.url), "utf8");
  return JSON.parse(text) as Record<string, unknown>;
}

describe("versioned planning protocol", () => {
  test("strictly validates project definitions and virtual work evidence", async () => {
    const request = await fixture("sat");
    const project = request.projects[0]!;
    const task = request.tasks[0]!;
    const coarse = {
      ...request,
      projects: [{
        ...project,
        definitionStatus: "COARSE",
        commitment: "COMMITTED",
        projectEffortMinutes: 180,
        explicitEffortMinutes: 150,
        remainingExplicitEffortMinutes: 150,
        virtualEffortMinutes: 30,
        defaultWorkMode: "Deep",
        planningChunkMinutes: 30,
        estimateConfidence: "Medium",
        diagnostics: [],
      }],
      tasks: [{
        ...task,
        id: "essay:virtual:1",
        durationMinutes: 30,
        deadlineSource: "project",
        prerequisiteIds: [],
        evidence: project.evidence,
        workType: "virtual",
        virtualWork: {
          projectId: "essay",
          ordinal: 1,
          chunkCount: 1,
          estimateConfidence: "Medium",
          projectEvidence: project.evidence,
        },
      }],
      intentions: [],
    };
    expect(planningRequestSchema.parse(coarse)).toEqual(coarse);
    expect(planningRequestSchema.safeParse({
      ...coarse,
      projects: [{ ...coarse.projects[0], estimateConfidence: "Maybe" }],
    }).success).toBe(false);
    expect(planningRequestSchema.safeParse({
      ...coarse,
      tasks: [{ ...coarse.tasks[0], virtualWork: null }],
    }).success).toBe(false);
    expect(planningRequestSchema.safeParse({
      ...coarse,
      projects: [{ ...coarse.projects[0], undeclaredPolicy: true }],
    }).success).toBe(false);
  });

  test("rejects unsupported protocol versions", async () => {
    const request = await fixture("sat");
    expect(planningRequestSchema.safeParse({
      ...request,
      protocolVersion: "lifeos-planning/v1",
    }).success).toBe(false);
  });

  test("records protocol and solver versions in every response", async () => {
    const response = await solvePlanningRequest(await fixture("sat"));
    expect(planningResponseSchema.parse(response)).toEqual(response);
    expect(response.protocolVersion).toBe(PROTOCOL_VERSION);
    expect(response.solverVersion).toBe(SOLVER_VERSION);
  });

  test("rejects pre-v2 responses without portfolio proof fields", async () => {
    const response = await solvePlanningRequest(await fixture("sat"));
    const { negotiationResults: _negotiationResults, ...responseWithoutNegotiation } = response;
    const { deadlineMargins: _baselineMargins, ...oldBaseline } = response.baseline!;
    expect(planningResponseSchema.safeParse({
      ...responseWithoutNegotiation,
      baseline: oldBaseline,
      baselinePortfolio: undefined,
      scenarioPortfolio: undefined,
    }).success).toBe(false);
  });

  test("accepts pre-extension comparison fields", async () => {
    const request = await fixture("unsat");
    const response = await solvePlanningRequest({
      ...request,
      scenario: { id: "unlock", reservations: [], unlockedCommitmentIds: ["fixed-task"],
        estimateChanges: [], intentionChanges: [] },
    });
    const { addedTaskIds: _added, droppedTaskIds: _dropped,
      safetyTransition: _safety, resilienceTransition: _resilience,
      taskStartDeltas: _starts, intentionAllocationDeltas: _intentions,
      reservePlacementDelta: _reserve, stressFeasibilityTransitions: _stress,
      ...oldComparison } = response.comparison!;
    const parsed = planningResponseSchema.parse({ ...response, comparison: oldComparison });
    expect(parsed.comparison?.addedTaskIds).toEqual([]);
    expect(parsed.comparison?.taskStartDeltas).toEqual([]);
    expect(parsed.comparison?.intentionAllocationDeltas).toEqual([]);
    expect(parsed.comparison?.reservePlacementDelta).toEqual(expect.objectContaining({
      countDelta: 0,
      minutesDelta: 0,
    }));
  });

  test("defaults releaseTime to null for v1 requests", async () => {
    const request = await fixture("sat");
    expect(request.tasks.every((task) => task.releaseTime === null)).toBe(true);
  });

  test("validates negotiation query bounds and scenario scope", async () => {
    const request = await fixture("sat");
    const query = {
      id: "gaming",
      kind: "maximum-deadline-only-discretionary-duration" as const,
      scope: "baseline" as const,
      start: 60,
      maximumEnd: 540,
    };
    expect(planningRequestSchema.safeParse({
      ...request,
      negotiationQueries: [{ ...query, maximumEnd: 30 }],
    }).success).toBe(false);
    expect(planningRequestSchema.safeParse({
      ...request,
      negotiationQueries: [{ ...query, scope: "scenario" }],
    }).success).toBe(false);
  });

  test("validates references, duplicate references, and scenario invariants", async () => {
    const request = await fixture("sat");
    expect(planningRequestSchema.safeParse({
      ...request,
      tasks: [{ ...request.tasks[0]!, projectId: "missing" }, ...request.tasks.slice(1)],
    }).success).toBe(false);
    expect(planningRequestSchema.safeParse({
      ...request,
      tasks: request.tasks.map((task, index) => index === 1
        ? { ...task, prerequisiteIds: ["research", "research"] } : task),
    }).success).toBe(false);
    const scenario = {
      id: "invalid-scenario",
      reservations: [{ id: "reservation", start: 60, end: 76, kind: "calendar" as const }],
      unlockedCommitmentIds: [],
      estimateChanges: [],
      intentionChanges: [],
    };
    expect(planningRequestSchema.safeParse({ ...request, scenario }).success).toBe(false);
    expect(planningRequestSchema.safeParse({
      ...request,
      scenario: {
        ...scenario,
        reservations: [],
        intentionChanges: [{ intentionId: "philosophy", minimumMinutes: 250 }],
      },
    }).success).toBe(false);
    expect(planningRequestSchema.safeParse({
      ...request,
      scenario: {
        ...scenario,
        reservations: [],
        estimateMultipliers: [{ taskId: "missing", percentage: 25 }],
      },
    }).success).toBe(false);
    expect(planningRequestSchema.safeParse({
      ...request,
      scenario: {
        ...scenario,
        reservations: [],
        estimateMultipliers: [{ taskId: "research", percentage: -1 }],
      },
    }).success).toBe(false);
  });

  test("applies estimate replacements before quantized percentage multipliers", async () => {
    const request = await fixture("sat");
    const applied = applyScenario(request, {
      id: "replacement-plus-overrun",
      reservations: [],
      unlockedCommitmentIds: [],
      estimateChanges: [{ taskId: "research", durationMinutes: 30 }],
      estimateMultipliers: [{ taskId: "research", percentage: 10 }],
      intentionChanges: [],
    });
    expect(applied.tasks.find((task) => task.id === "research")?.durationMinutes).toBe(45);
  });

  test("applies composable project changes before deriving virtual chunks and deadlines", async () => {
    const request = await fixture("sat");
    const project = { ...request.projects[0]!, definitionStatus: "COARSE" as const,
      projectEffortMinutes: 210, virtualEffortMinutes: 60,
      defaultWorkMode: "Deep", planningChunkMinutes: 45,
      estimateConfidence: "Low" as const };
    const explicit = request.tasks.map((task) => ({ ...task, deadlineSource: "project" as const }));
    const baseline = planningRequestSchema.parse({
      ...request, projects: [project], tasks: [
        ...explicit,
        { ...explicit[0]!, id: "essay:virtual:1", durationMinutes: 45,
          prerequisiteIds: [], evidence: project.evidence,
          workType: "virtual", deadlineSource: "project",
          virtualWork: { projectId: "essay", ordinal: 1, chunkCount: 2,
            estimateConfidence: "Low", projectEvidence: project.evidence } },
        { ...explicit[0]!, id: "essay:virtual:2", durationMinutes: 15,
          prerequisiteIds: [], evidence: project.evidence,
          workType: "virtual", deadlineSource: "project",
          virtualWork: { projectId: "essay", ordinal: 2, chunkCount: 2,
            estimateConfidence: "Low", projectEvidence: project.evidence } },
      ], intentions: [],
    });
    const applied = applyScenario(baseline, {
      id: "reframe", reservations: [], unlockedCommitmentIds: [], estimateChanges: [],
      intentionChanges: [], projectChanges: [{ projectId: "essay",
        projectEffortMinutes: 240, deadline: 540, defaultWorkMode: "Shallow",
        planningChunkMinutes: 60, estimateConfidence: "High" }],
    });
    expect(applied.projects[0]).toEqual(expect.objectContaining({
      projectEffortMinutes: 240, virtualEffortMinutes: 90, deadline: 540,
      definitionStatus: "COARSE", estimateConfidence: "High",
    }));
    expect(applied.tasks.filter((task) => task.workType === "virtual").map((task) => ({
      id: task.id, duration: task.durationMinutes, deadline: task.deadline,
      mode: task.workMode, confidence: task.virtualWork?.estimateConfidence,
    }))).toEqual([
      { id: "essay:virtual:1", duration: 60, deadline: 540,
        mode: "Shallow", confidence: "High" },
      { id: "essay:virtual:2", duration: 30, deadline: 540,
        mode: "Shallow", confidence: "High" },
    ]);
    expect(baseline.projects[0]!.projectEffortMinutes).toBe(210);

    const response = await solvePlanningRequest(planningRequestSchema.parse({
      ...baseline,
      scenario: {
        id: "reframe", reservations: [], unlockedCommitmentIds: [], estimateChanges: [],
        intentionChanges: [], projectChanges: [{ projectId: "essay",
          projectEffortMinutes: 240, deadline: 540, commitment: "UNCOMMITTED" }],
      },
    }));
    expect(response.comparison?.projectDeltas).toEqual([
      expect.objectContaining({
        projectId: "essay", baselineEffortMinutes: 210, scenarioEffortMinutes: 240,
        effortDeltaMinutes: 30, baselineCommitment: "COMMITTED",
        scenarioCommitment: "UNCOMMITTED", scenarioPortfolioStatus: "UNCOMMITTED",
      }),
    ]);
  }, 30_000);
});

describe("adjustable schedule candidate protocol", () => {
  test("strictly validates candidate identity, edits, and source references", async () => {
    const request = await fixture("sat");
    const candidate = {
      candidateId: "candidate-1",
      revision: 4,
      capturedInputFingerprint: "sha256:current-input",
      exactPlacements: [{ taskId: "research", start: 270 }],
      exclusions: [{ kind: "TASK" as const, taskId: "optional-reading" }],
      estimateOverrides: [{ kind: "TASK" as const, taskId: "research", durationMinutes: 75 }],
      currentPlanSeeds: [{ kind: "TASK" as const, taskId: "draft", start: 345, end: 435 }],
    };
    expect(planningRequestSchema.parse({ ...request, candidate }).candidate).toEqual(candidate);
    expect(planningRequestSchema.safeParse({
      ...request,
      candidate: { ...candidate, revision: -1 },
    }).success).toBe(false);
    expect(planningRequestSchema.safeParse({
      ...request,
      candidate: { ...candidate, exactPlacements: [{ taskId: "missing", start: 270 }] },
    }).success).toBe(false);
    expect(planningRequestSchema.safeParse({
      ...request,
      candidate: { ...candidate,
        exclusions: [{ kind: "TASK", taskId: "research" }],
        exactPlacements: [{ taskId: "research", start: 270 }] },
    }).success).toBe(false);
    expect(planningRequestSchema.safeParse({
      ...request,
      candidate: { ...candidate, undeclaredEdit: true },
    }).success).toBe(false);
  });

  test("honors exact placement, exclusion, override, identity, and rationale", async () => {
    const original = await fixture("sat");
    const request = planningRequestSchema.parse({
      ...original,
      requestId: "candidate-request-4",
      candidate: {
        candidateId: "candidate-1",
        revision: 4,
        capturedInputFingerprint: "sha256:current-input",
        exactPlacements: [{ taskId: "research", start: 270 }],
        exclusions: [{ kind: "TASK", taskId: "optional-reading" }],
        estimateOverrides: [{ kind: "TASK", taskId: "research", durationMinutes: 75 }],
        currentPlanSeeds: [{ kind: "TASK", taskId: "draft", start: 345, end: 435 }],
      },
    });
    const response = await solvePlanningRequest(request);
    expect(response.candidateIdentity).toEqual({
      candidateId: "candidate-1",
      revision: 4,
      capturedInputFingerprint: "sha256:current-input",
      normalizedRequestId: "candidate-request-4",
    });
    expect(response.baseline?.placements).toEqual(expect.arrayContaining([
      expect.objectContaining({ taskId: "research", start: 270, end: 345,
        sourceId: "research", demandKind: "TASK", rationale: "exact-user-placement" }),
      expect.objectContaining({ taskId: "draft", start: 345, end: 435,
        sourceId: "draft", rationale: "current-plan-seed-kept" }),
    ]));
    expect(response.baseline?.omissions).toContainEqual(expect.objectContaining({
      sourceId: "optional-reading", rationale: "user-excluded", durationMinutes: 45,
    }));
    expect(response.baseline?.candidateEvidence).toEqual(expect.objectContaining({
      exactPlacementTaskIds: ["research"],
      excludedSourceIds: ["optional-reading"],
      estimateOverrideSourceIds: ["research"],
      seed: { totalCount: 1, keptCount: 1, movedCount: 0, omittedCount: 0,
        keptSourceIds: ["draft"], movedSourceIds: [], omittedSourceIds: [] },
      deadlineStatus: "SATISFIED",
    }));
    expect(original.tasks.find((task) => task.id === "research")?.durationMinutes).toBe(60);
    expect(verifyPlanningResponse(request, response)).toEqual([]);
  }, 30_000);

  test("reports an exact placement conflict instead of adjusting it", async () => {
    const request = await fixture("sat");
    const candidateRequest = planningRequestSchema.parse({
      ...request,
      candidate: {
        candidateId: "candidate-conflict", revision: 1,
        capturedInputFingerprint: "sha256:conflict",
        exactPlacements: [{ taskId: "research", start: 210 }],
        exclusions: [], estimateOverrides: [], currentPlanSeeds: [],
      },
    });
    const response = await solvePlanningRequest(candidateRequest);
    expect(response.baseline?.feasibility).toBe("PROVEN INFEASIBLE");
    expect(response.baseline?.placements).toEqual([]);
    expect(response.baseline?.conflicts.map((conflict) => conflict.kind)).toEqual(
      expect.arrayContaining(["exact-placement", "travel"]),
    );
    expect(verifyPlanningResponse(candidateRequest, response)).toEqual([]);
  });

  test("keeps current-plan seeds stable and rejects stale revision evidence", async () => {
    const base = await fixture("sat");
    const request = planningRequestSchema.parse({
      ...base,
      busy: [], reserve: [],
      candidate: {
        candidateId: "candidate-seed", revision: 2,
        capturedInputFingerprint: "sha256:seed",
        exactPlacements: [], exclusions: [], estimateOverrides: [],
        currentPlanSeeds: [
          { kind: "TASK", taskId: "research", start: 60, end: 120 },
          { kind: "TASK", taskId: "draft", start: 120, end: 210 },
        ],
      },
    });
    const response = await solvePlanningRequest(request);
    expect(response.baseline?.placements.filter((placement) =>
      placement.rationale === "current-plan-seed-kept").map((placement) => placement.taskId))
      .toEqual(["research", "draft"]);
    const nextRevision = planningRequestSchema.parse({
      ...request,
      requestId: "candidate-seed-next",
      candidate: { ...request.candidate!, revision: 3 },
    });
    expect(verifyPlanningResponse(nextRevision, response)).toContain(
      "Response identity does not exactly match the normalized candidate request.",
    );
  });

  test("attributes coarse project capacity without inventing task identity", async () => {
    const base = await fixture("sat");
    const project = {
      ...base.projects[0]!, definitionStatus: "COARSE" as const,
      projectEffortMinutes: 60, explicitEffortMinutes: 0,
      remainingExplicitEffortMinutes: 0, virtualEffortMinutes: 60,
      defaultWorkMode: "Deep", planningChunkMinutes: 30,
      estimateConfidence: "Medium" as const,
    };
    const virtualTasks = [1, 2].map((ordinal) => ({
      ...base.tasks[0]!, id: `essay:virtual:${ordinal}`,
      durationMinutes: 30, deadlineSource: "project" as const,
      prerequisiteIds: [], evidence: project.evidence, workType: "virtual" as const,
      virtualWork: { projectId: "essay", ordinal, chunkCount: 2,
        estimateConfidence: "Medium" as const, projectEvidence: project.evidence },
    }));
    const request = planningRequestSchema.parse({
      ...base, tasks: virtualTasks, projects: [project], busy: [], reserve: [], intentions: [],
      candidate: {
        candidateId: "candidate-capacity", revision: 1,
        capturedInputFingerprint: "sha256:capacity",
        exactPlacements: [], exclusions: [],
        estimateOverrides: [{ kind: "PROJECT_CAPACITY", projectId: "essay",
          durationMinutes: 45 }],
        currentPlanSeeds: [
          { kind: "PROJECT_CAPACITY", projectId: "essay", start: 60, end: 90 },
          { kind: "PROJECT_CAPACITY", projectId: "essay", start: 90, end: 105 },
        ],
      },
    });
    const response = await solvePlanningRequest(request);
    expect(response.baseline?.placements.map((placement) => ({
      sourceId: placement.sourceId,
      demandKind: placement.demandKind,
      minutes: placement.end - placement.start,
      confidence: placement.estimateConfidence,
      rationale: placement.rationale,
    }))).toEqual([
      { sourceId: "essay", demandKind: "PROJECT_CAPACITY", minutes: 30,
        confidence: "Medium", rationale: "current-plan-seed-kept" },
      { sourceId: "essay", demandKind: "PROJECT_CAPACITY", minutes: 15,
        confidence: "Medium", rationale: "current-plan-seed-kept" },
    ]);
    expect(response.baseline?.candidateEvidence).toEqual(expect.objectContaining({
      estimateConfidenceStatus: "MEDIUM",
      capacityStatus: "SATISFIED",
      placedCapacityMinutes: 45,
      omittedCapacityMinutes: 0,
    }));
    expect(verifyPlanningResponse(request, response)).toEqual([]);

    const excludedRequest = planningRequestSchema.parse({
      ...request,
      requestId: "candidate-capacity-excluded",
      candidate: { ...request.candidate!, revision: 2,
        exclusions: [{ kind: "PROJECT_CAPACITY", projectId: "essay" }],
        estimateOverrides: [], currentPlanSeeds: [] },
    });
    const excluded = await solvePlanningRequest(excludedRequest);
    expect(excluded.baseline?.placements).toEqual([]);
    expect(excluded.baseline?.omissions).toEqual([expect.objectContaining({
      demandKind: "PROJECT_CAPACITY", sourceId: "essay", taskId: null,
      rationale: "user-excluded", durationMinutes: 60,
    })]);
    expect(verifyPlanningResponse(excludedRequest, excluded)).toEqual([]);
  }, 30_000);

  test("independent verification rejects attribution, rationale, and planning-evidence tampering", async () => {
    const base = await fixture("sat");
    const request = planningRequestSchema.parse({
      ...base, busy: [], reserve: [],
      candidate: {
        candidateId: "candidate-verify", revision: 1,
        capturedInputFingerprint: "sha256:verify",
        exactPlacements: [{ taskId: "research", start: 60 }],
        exclusions: [], estimateOverrides: [], currentPlanSeeds: [],
      },
    });
    const response = await solvePlanningRequest(request);
    const tampered = planningResponseSchema.parse({
      ...response,
      baseline: {
        ...response.baseline!,
        placements: response.baseline!.placements.map((placement) =>
          placement.taskId === "research"
            ? { ...placement, sourceId: "draft", rationale: "solver-selected" }
            : placement),
        candidateEvidence: {
          ...response.baseline!.candidateEvidence!,
          deadlineStatus: "UNKNOWN",
        },
      },
    });
    expect(verifyPlanningResponse(request, tampered).join(" ")).toMatch(
      /source attribution|rationale|planning evidence/,
    );
  });
});

describe("Z3 feasibility and optimization", () => {
  test("proves ready projects independently and discloses the modeled portfolio subset", async () => {
    const request = await fixture("sat");
    const essay = request.projects[0]!;
    const book = { ...essay, id: "book", projectEffortMinutes: 360,
      explicitEffortMinutes: 360, remainingExplicitEffortMinutes: 360,
      evidence: { sourceId: "org:book", kind: "project" } };
    const someday = { ...essay, id: "someday", commitment: "UNCOMMITTED" as const,
      evidence: { sourceId: "org:someday", kind: "project" } };
    const essayTask = { ...request.tasks[0]!, durationMinutes: 360, prerequisiteIds: [] };
    const bookTask = { ...essayTask, id: "book-task", projectId: "book",
      evidence: { sourceId: "org:book-task", kind: "task" } };
    const somedayTask = { ...essayTask, id: "someday-task", projectId: "someday",
      evidence: { sourceId: "org:someday-task", kind: "task" } };
    const scoped = planningRequestSchema.parse({
      ...request, horizon: { start: 0, end: 480 }, calendarCoverageEnd: 480,
      availabilityCoverageEnd: 480,
      tasks: [essayTask, bookTask, somedayTask], projects: [essay, book, someday],
      availability: [{ ...request.availability[0]!, start: 0, end: 480 }],
      busy: [], reserve: [], intentions: [],
    });
    const response = await solvePlanningRequest(scoped);
    expect(response.baselinePortfolio).toEqual(expect.objectContaining({
      definitionStatus: "COMPLETE",
      modeledProjectIds: ["book", "essay"],
      excludedProjectIds: ["someday"],
      feasibility: "PROVEN INFEASIBLE",
    }));
    expect(response.baselinePortfolio?.projectResults).toEqual(expect.arrayContaining([
      expect.objectContaining({ projectId: "essay", isolatedFeasibility: "FEASIBLE" }),
      expect.objectContaining({ projectId: "book", isolatedFeasibility: "FEASIBLE" }),
      expect.objectContaining({ projectId: "someday", isolatedFeasibility: "UNCOMMITTED",
        portfolioStatus: "UNCOMMITTED" }),
    ]));
    expect(response.baselinePortfolio?.projectResults
      .filter((result) => result.isolatedResult !== null)
      .every((result) => result.isolatedResult!.assumptions.every((assumption) =>
        !assumption.startsWith("Internal model verification failed:")))).toBe(true);
  }, 30_000);

  test("keeps cross-project prerequisite closure and incomplete commitments explicit", async () => {
    const request = await fixture("sat");
    const essay = request.projects[0]!;
    const library = { ...essay, id: "library", commitment: "UNCOMMITTED" as const,
      projectEffortMinutes: 60, explicitEffortMinutes: 60,
      remainingExplicitEffortMinutes: 60,
      evidence: { sourceId: "org:library", kind: "project" } };
    const undefinedProject = { ...essay, id: "undefined-project",
      definitionStatus: "INCOMPLETE" as const, projectEffortMinutes: null,
      explicitEffortMinutes: 0, remainingExplicitEffortMinutes: 0,
      diagnostics: [{ sourceId: "org:undefined", kind: "missing-project-effort" }],
      evidence: { sourceId: "org:undefined", kind: "project" } };
    const prerequisite = { ...request.tasks[0]!, id: "library-task", projectId: "library",
      durationMinutes: 60, deadline: null, prerequisiteIds: [],
      evidence: { sourceId: "org:library-task", kind: "task" } };
    const dependent = { ...request.tasks[1]!, durationMinutes: 60,
      prerequisiteIds: ["library-task"] };
    const response = await solvePlanningRequest(planningRequestSchema.parse({
      ...request, tasks: [prerequisite, dependent],
      projects: [essay, library, undefinedProject], busy: [], reserve: [], intentions: [],
    }));
    const result = response.baselinePortfolio!.projectResults.find((item) =>
      item.projectId === "essay")!;
    expect(result.borrowedPrerequisiteTaskIds).toEqual(["library-task"]);
    expect(result.borrowedPrerequisiteProjectIds).toEqual(["library"]);
    expect(result.isolatedResult?.placements.map((item) => item.taskId).sort()).toEqual([
      "draft", "library-task",
    ]);
    expect(response.baselinePortfolio).toEqual(expect.objectContaining({
      definitionStatus: "INCOMPLETE",
      modeledSubset: true,
      feasibility: "PROVEN FEASIBLE",
    }));
  }, 30_000);

  test("matches stable SAT and UNSAT semantic goldens", async () => {
    const sat = planningResponseSchema.parse(await solvePlanningRequest(await fixture("sat")));
    const unsat = planningResponseSchema.parse(await solvePlanningRequest(await fixture("unsat")));
    const satIntentions = Object.fromEntries(
      sat.baseline!.intentions.map((item) => [item.id, item.allocatedMinutes]).sort(),
    );
    expect({
      status: sat.status,
      feasibility: sat.baseline!.feasibility,
      safety: sat.baseline!.safety,
      placementTaskIds: sat.baseline!.placements.map((item) => item.taskId),
      placementKinds: sat.baseline!.placements.map((item) => item.kind),
      intentionAllocatedMinutes: satIntentions,
      stressResults: sat.baseline!.stressResults,
      portfolioDefinitionStatus: sat.baselinePortfolio!.definitionStatus,
      modeledProjectIds: sat.baselinePortfolio!.modeledProjectIds,
      projectStatuses: sat.baselinePortfolio!.projectResults.map((item) => ({
        projectId: item.projectId,
        definitionStatus: item.definitionStatus,
        isolatedFeasibility: item.isolatedFeasibility,
        proofKind: item.proofKind,
        portfolioStatus: item.portfolioStatus,
      })),
      negotiationResults: sat.negotiationResults,
    }).toEqual(await golden("sat"));

    const expectedUnsat = await golden("unsat") as {
      requiredConflictKinds: string[];
      conflictSourceIds: string[];
      [key: string]: unknown;
    };
    const { requiredConflictKinds, ...unsatProjection } = expectedUnsat;
    expect({
      status: unsat.status,
      feasibility: unsat.baseline!.feasibility,
      safety: unsat.baseline!.safety,
      conflictSourceIds: [...new Set(unsat.baseline!.conflicts.map((item) => item.sourceId))].sort(),
      conflictProjectIds: [...new Set(
        unsat.baseline!.conflicts.flatMap((item) => item.projectIds),
      )].sort(),
      placementTaskIds: unsat.baseline!.placements.map((item) => item.taskId),
      portfolioDefinitionStatus: unsat.baselinePortfolio!.definitionStatus,
      projectStatuses: unsat.baselinePortfolio!.projectResults.map((item) => ({
        projectId: item.projectId,
        isolatedFeasibility: item.isolatedFeasibility,
        portfolioStatus: item.portfolioStatus,
      })),
      negotiationResults: unsat.negotiationResults,
    }).toEqual(unsatProjection);
    expect(unsat.baseline!.conflicts.map((item) => item.kind)).toEqual(
      expect.arrayContaining(requiredConflictKinds),
    );
  }, 30_000);

  test("returns a deterministic, independently valid satisfiable model", async () => {
    const request = await fixture("sat");
    const first = await solvePlanningRequest(request);
    const second = await solvePlanningRequest(request);
    expect(first).toEqual(second);
    expect(first.baseline?.feasibility).toBe("PROVEN FEASIBLE");
    expect(first.baseline?.safety).toBe("SAFE");
    expect(first.baseline && verifyHardConstraints(request, first.baseline)).toEqual([]);
    expect(first.baseline?.placements.map((placement) => placement.taskId)).toEqual([
      "research",
      "draft",
    ]);
    expect(verifyHardConstraints(request, {
      ...first.baseline!,
      placements: first.baseline!.placements.slice(1),
    })).toContain("Mandatory task research is not placed.");
  }, 30_000);

  test("enforces and independently verifies task release times", async () => {
    const request = await fixture("sat");
    const released = planningRequestSchema.parse({
      ...request,
      tasks: request.tasks.map((task) => task.id === "research"
        ? { ...task, releaseTime: 300 } : task),
    });
    const response = await solvePlanningRequest(released);
    const research = response.baseline?.placements.find((item) => item.taskId === "research");
    expect(research?.start).toBeGreaterThanOrEqual(300);
    expect(verifyHardConstraints(released, response.baseline!)).toEqual([]);
    expect(verifyHardConstraints(released, {
      ...response.baseline!,
      placements: response.baseline!.placements.map((placement) =>
        placement.taskId === "research"
          ? { ...placement, start: 285, end: 345 }
          : placement),
    })).toContain("research starts before its release time.");
  });

  test("returns structured hard and safety deadline margins", async () => {
    const response = await solvePlanningRequest(await fixture("sat"));
    expect(response.baseline?.deadlineMargins).toEqual([
      expect.objectContaining({
        taskId: "draft",
        projectId: "essay",
        deadline: 480,
        hardDeadlineMarginMinutes: expect.any(Number),
        safetyBufferMinutes: 30,
        safetyMarginMinutes: expect.any(Number),
      }),
      expect.objectContaining({
        taskId: "research",
        projectId: "essay",
        deadline: 480,
        hardDeadlineMarginMinutes: expect.any(Number),
        safetyBufferMinutes: 30,
        safetyMarginMinutes: expect.any(Number),
      }),
    ]);
    for (const margin of response.baseline!.deadlineMargins) {
      expect(margin.hardDeadlineMarginMinutes).toBe(margin.deadline - margin.completionTime);
      expect(margin.safetyMarginMinutes).toBe(
        margin.hardDeadlineMarginMinutes - margin.safetyBufferMinutes,
      );
    }
  });

  test("attributes shared conflicts to every involved task and project", async () => {
    const request = await fixture("sat");
    const first = { ...request.tasks[0]!, durationMinutes: 300, prerequisiteIds: [] };
    const secondProject = { ...request.projects[0]!, id: "book",
      evidence: { sourceId: "org:book", kind: "project" } };
    const second = { ...first, id: "book-task", projectId: "book",
      evidence: { sourceId: "org:book-task", kind: "task" } };
    const response = await solvePlanningRequest(planningRequestSchema.parse({
      ...request,
      tasks: [first, second],
      projects: [request.projects[0]!, secondProject],
      busy: [], reserve: [], intentions: [],
    }));
    expect(response.baseline?.feasibility).toBe("PROVEN INFEASIBLE");
    expect(response.baseline?.conflicts).toEqual(expect.arrayContaining([
      expect.objectContaining({
        kind: "task-overlap",
        taskIds: ["book-task", "research"],
        projectIds: ["book", "essay"],
        shared: false,
      }),
    ]));
  });

  test("returns mapped source constraints for an impossible model", async () => {
    const response = await solvePlanningRequest(await fixture("unsat"));
    expect(response.baseline?.feasibility).toBe("PROVEN INFEASIBLE");
    expect(response.baseline?.conflicts.map((conflict) => conflict.kind)).toEqual(
      expect.arrayContaining(["fixed-start", "deadline"]),
    );
    expect(response.baseline?.conflicts.every((conflict) =>
      conflict.sourceId === "org:fixed-task")).toBe(true);
    expect(response.baseline?.conflicts.find((conflict) => conflict.kind === "fixed-start")
      ?.relaxation).toEqual({
        type: "unlock-commitment",
        text: "Unlock this fixed commitment so it can be rescheduled.",
      });
  });

  test("maps availability, preflight, and safety conflicts to actionable relaxations", async () => {
    const request = await fixture("sat");
    const unavailable = await solvePlanningRequest({ ...request, availability: [] });
    const availabilityConflict = unavailable.baseline?.conflicts.find((conflict) =>
      conflict.kind === "availability");
    expect(availabilityConflict?.relaxation?.type).toBe("add-compatible-availability");
    expect(availabilityConflict).toEqual(expect.objectContaining({
      taskIds: [expect.any(String)],
      projectIds: ["essay"],
      shared: true,
    }));

    const unknownDuration = await solvePlanningRequest({
      ...request,
      tasks: request.tasks.map((task) => task.id === "research"
        ? { ...task, durationMinutes: null } : task),
    });
    expect(unknownDuration.baseline?.conflicts[0]).toEqual(expect.objectContaining({
      kind: "unknown-duration",
      relaxation: expect.objectContaining({ type: "provide-duration-estimate" }),
    }));

    const reserve = request.reserve[0]!;
    const tight = await solvePlanningRequest({
      ...request,
      reserve: [{ ...reserve, minimumMinutes: 300 }],
    });
    const safetyRelaxation = tight.baseline?.conflicts.find((conflict) =>
      conflict.kind === "reserve")?.relaxation;
    expect(safetyRelaxation?.type).toBe("adjust-safety-policy");
    expect(safetyRelaxation?.text).toMatch(/does not weaken the hard deadline/);
  });

  test("returns UNKNOWN without a safety claim when the timeout budget is zero", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest({ ...request, timeoutMs: 0 });
    expect(response.baseline?.feasibility).toBe("UNKNOWN");
    expect(response.baseline?.safety).toBeNull();
    expect(response.baseline?.assumptions.join(" ")).toMatch(/zero-millisecond/);
  });

  test("keeps deadline feasibility separate from reserve safety", async () => {
    const request = await fixture("sat");
    const reserve = request.reserve[0]!;
    const response = await solvePlanningRequest({
      ...request,
      reserve: [{ ...reserve, minimumMinutes: 300 }],
    });
    expect(response.baseline?.feasibility).toBe("PROVEN FEASIBLE");
    expect(response.baseline?.safety).toBe("TIGHT");
    expect(response.baseline?.reservePlacements).toEqual([]);
  });

  test("reserve protects usable availability rather than wall-clock slack", async () => {
    const request = await fixture("sat");
    const reserve = request.reserve[0]!;
    const response = await solvePlanningRequest({
      ...request,
      reserve: [{
        ...reserve,
        envelopeStart: 0,
        envelopeEnd: 60,
        minimumMinutes: 30,
      }],
    });
    expect(response.baseline?.feasibility).toBe("PROVEN FEASIBLE");
    expect(response.baseline?.safety).toBe("TIGHT");
  });

  test("incomplete mandatory normalization returns UNKNOWN", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest({
      ...request,
      hardIssues: ["Nightly sleep configuration is incomplete."],
    });
    expect(response.baseline?.feasibility).toBe("UNKNOWN");
    expect(response.baseline?.safety).toBeNull();
    expect(response.baseline?.assumptions).toContain(
      "Nightly sleep configuration is incomplete.",
    );
  });

  test("credits overlapping intentions without double-counting capacity", async () => {
    const response = await solvePlanningRequest(await fixture("sat"));
    expect(response.baseline?.intentions).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: "philosophy", allocatedMinutes: 150 }),
      expect.objectContaining({ id: "essay-intention", allocatedMinutes: 150 }),
    ]));
    expect(response.baseline?.placements).toHaveLength(2);
  });

  test("unlocks only the fixed-start equality in a scenario", async () => {
    const request = await fixture("unsat");
    const response = await solvePlanningRequest({
      ...request,
      scenario: {
        id: "unlock-fixed",
        reservations: [],
        unlockedCommitmentIds: ["fixed-task"],
        estimateChanges: [],
        intentionChanges: [],
      },
    });
    expect(response.baseline?.feasibility).toBe("PROVEN INFEASIBLE");
    expect(response.scenario?.feasibility).toBe("PROVEN FEASIBLE");
    expect(response.scenario?.unlockedCommitmentIds).toEqual(["fixed-task"]);
    expect(response.scenario?.placements[0]?.end).toBeLessThanOrEqual(180);
  });

  test("models sleep as a contiguous flexible physical constraint", async () => {
    const request = await fixture("unsat");
    const task = request.tasks[0]!;
    const response = await solvePlanningRequest({
      ...request,
      tasks: [{ ...task, deadline: 300, fixedStart: 0 }],
      sleep: [{
        id: "night",
        envelopeStart: 0,
        envelopeEnd: 120,
        minimumMinutes: 120,
        evidence: { sourceId: "planning:sleep", kind: "sleep-default" },
      }],
    });
    expect(response.baseline?.feasibility).toBe("PROVEN INFEASIBLE");
    expect(response.baseline?.conflicts.some((conflict) => conflict.kind === "sleep")).toBe(true);
  });

  test("does not select optional unresolved WAITING tasks", async () => {
    const request = await fixture("sat");
    const waiting = {
      ...request.tasks[2]!,
      state: "WAITING" as const,
      unresolvedWaiting: true,
      priority: "A" as const,
      impact: "High" as const,
    };
    const response = await solvePlanningRequest({
      ...request,
      tasks: [waiting],
      projects: [],
      intentions: [],
      busy: [],
      reserve: [],
    });
    expect(response.baseline?.feasibility).toBe("PROVEN FEASIBLE");
    expect(response.baseline?.placements).toEqual([]);
  });

  test("aligns movable work, sleep, and reserve while preserving an exact fixed start", async () => {
    const request = await fixture("sat");
    const fixed = {
      ...request.tasks[0]!, id: "fixed", projectId: null, durationMinutes: 17,
      deadline: null, fixedStart: 61, prerequisiteIds: [], mandatory: true,
    };
    const response = await solvePlanningRequest({
      ...request,
      tasks: [fixed], projects: [], intentions: [], busy: [], reserve: [],
      sleep: [{ id: "sleep", envelopeStart: 90, envelopeEnd: 180,
        minimumMinutes: 30, evidence: { sourceId: "sleep", kind: "sleep" } }],
    });
    expect(response.baseline?.placements[0]).toEqual(expect.objectContaining({
      start: 61, end: 78, kind: "fixed",
    }));
    expect(response.baseline!.sleepPlacements[0]!.start % 15).toBe(0);
    expect(response.baseline!.sleepPlacements[0]!.end % 15).toBe(0);
  });

  test("stress failures mark a feasible baseline fragile", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest({
      ...request,
      stressProfiles: [{
        id: "lose-deep-window",
        description: "Lose the only deep work window",
        scenario: {
          id: "stress-reservation",
          reservations: [{
            id: "unexpected-busy",
            start: 60,
            end: 540,
            kind: "scenario-reservation",
          }],
          unlockedCommitmentIds: [],
          estimateChanges: [],
          intentionChanges: [],
        },
      }],
    });
    expect(response.baseline?.feasibility).toBe("PROVEN FEASIBLE");
    expect(response.baseline?.resilience).toBe("FRAGILE");
    expect(response.baseline?.stressResults[0]?.feasibility).toBe("PROVEN INFEASIBLE");
  });

  test("stress multipliers compose with already scenario-adjusted estimates", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest({
      ...request,
      scenario: {
        id: "shorter-research", reservations: [], unlockedCommitmentIds: [],
        estimateChanges: [{ taskId: "research", durationMinutes: 15 }],
        intentionChanges: [],
      },
      stressProfiles: [{
        id: "estimate-overrun", description: "Research takes six times as long",
        scenario: {
          id: "estimate-overrun-scenario",
          reservations: [],
          unlockedCommitmentIds: [], estimateChanges: [],
          estimateMultipliers: [{ taskId: "research", percentage: 500 }],
          intentionChanges: [],
        },
      }],
    });
    expect(response.baseline?.resilience).toBe("FRAGILE");
    expect(response.scenario?.resilience).toBe("RESILIENT");
    expect(response.scenario?.stressResults).toHaveLength(1);
    expect(response.comparison).toEqual(expect.objectContaining({
      safetyTransition: { baseline: "SAFE", scenario: "SAFE" },
      resilienceTransition: { baseline: "FRAGILE", scenario: "RESILIENT" },
      intentionAllocationDeltas: expect.arrayContaining([
        expect.objectContaining({ intentionId: "philosophy", deltaMinutes: -45 }),
        expect.objectContaining({ intentionId: "essay-intention", deltaMinutes: -45 }),
      ]),
      stressFeasibilityTransitions: [{
        id: "estimate-overrun",
        baseline: "PROVEN INFEASIBLE",
        scenario: "PROVEN FEASIBLE",
      }],
    }));
  });

  test("comparison distinguishes added tasks from moved tasks", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest({
      ...request,
      busy: [], reserve: [], intentions: [],
      availability: [{ ...request.availability[0]!, end: 210 }],
      scenario: {
        id: "shorter-research", reservations: [], unlockedCommitmentIds: [],
        estimateChanges: [{ taskId: "research", durationMinutes: 15 }],
        intentionChanges: [],
      },
    });
    expect(response.comparison?.addedTaskIds).toContain("optional-reading");
    expect(response.comparison?.movedTaskIds).not.toContain("optional-reading");
    expect(response.comparison?.droppedTaskIds).toEqual([]);
    expect(response.comparison?.taskStartDeltas).toEqual(
      response.comparison?.movedTaskIds.map((taskId) => expect.objectContaining({
        taskId,
        baselineStart: expect.any(Number),
        scenarioStart: expect.any(Number),
        deltaMinutes: expect.any(Number),
      })),
    );
  });

  test("reports reserve placement count and minute deltas", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest({
      ...request,
      reserve: [{ ...request.reserve[0]!, minimumMinutes: 240 }],
      scenario: {
        id: "consume-reserve",
        reservations: [{
          id: "late-block",
          start: 480,
          end: 540,
          kind: "scenario-reservation",
        }],
        unlockedCommitmentIds: [],
        estimateChanges: [],
        intentionChanges: [],
      },
    });
    expect(response.baseline?.safety).toBe("SAFE");
    expect(response.scenario?.safety).toBe("TIGHT");
    expect(response.comparison?.reservePlacementDelta).toEqual({
      baselineCount: 1,
      scenarioCount: 0,
      countDelta: -1,
      baselineMinutes: 240,
      scenarioMinutes: 0,
      minutesDelta: -240,
    });
  });

  test("verifier rejects duplicate, extra, wrongly typed, and unaligned placements", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest(request);
    const baseline = response.baseline!;
    const errors = verifyHardConstraints(request, {
      ...baseline,
      placements: [
        ...baseline.placements,
        { ...baseline.placements[0]!, kind: "proposed", start: 61, end: 121 },
      ],
      sleepPlacements: [{ id: "extra", start: 1, end: 16 }],
      unlockedCommitmentIds: ["missing"],
    });
    expect(errors.join(" ")).toMatch(/Duplicate task placement/);
    expect(errors.join(" ")).toMatch(/placement kind|scheduling grid/);
    expect(errors.join(" ")).toMatch(/Sleep placements do not exactly match/);
    expect(errors.join(" ")).toMatch(/Unlocked commitment/);
  });

  test("independently verifies project ownership and returned deadline margins", async () => {
    const request = await fixture("sat");
    const baseline = (await solvePlanningRequest(request)).baseline!;
    const errors = verifyHardConstraints(request, {
      ...baseline,
      placements: baseline.placements.map((placement, index) => index === 0
        ? { ...placement, projectId: null } : placement),
      deadlineMargins: baseline.deadlineMargins.map((margin, index) => index === 0
        ? { ...margin, safetyMarginMinutes: margin.safetyMarginMinutes + 15 } : margin),
    });
    expect(errors.join(" ")).toMatch(/wrong project ownership/);
    expect(errors.join(" ")).toMatch(/deadline margin/);
  });

  test("property-checks generated returned placements against hard constraints", async () => {
    const base = await fixture("sat");
    await fc.assert(fc.asyncProperty(
      fc.integer({ min: 1, max: 8 }),
      async (units) => {
        const durationMinutes = units * 15;
        const task = {
          ...base.tasks[0]!,
          projectId: null,
          durationMinutes,
          deadline: 540,
          prerequisiteIds: [],
        };
        const request = planningRequestSchema.parse({
          ...base,
          requestId: `property-${units}`,
          defaultSafetyBufferMinutes: 0,
          tasks: [task],
          projects: [],
          busy: [],
          reserve: [],
          intentions: [],
        });
        const response = await solvePlanningRequest(request);
        expect(response.baseline?.feasibility).toBe("PROVEN FEASIBLE");
        expect(response.baseline && verifyHardConstraints(request, response.baseline)).toEqual([]);
      },
    ), { numRuns: 4 });
  }, 30_000);
});

describe("quantitative negotiation", () => {
  test("answers aligned project effort, work-window, start, and deadline queries", async () => {
    const base = await fixture("sat");
    const project = { ...base.projects[0]!, defaultWorkMode: "Deep",
      planningChunkMinutes: 15, estimateConfidence: "Medium" as const };
    const prepared = planningRequestSchema.parse({
      ...base,
      horizon: { start: 0, end: 480 }, calendarCoverageEnd: 480,
      availabilityCoverageEnd: 480, defaultSafetyBufferMinutes: 0,
      projects: [project], tasks: base.tasks.slice(0, 2).map((task) => ({
        ...task, deadlineSource: "project",
      })),
      availability: [{ ...base.availability[0]!, start: 0, end: 480 }],
      busy: [], reserve: [], intentions: [],
    });
    const coarse = planningRequestSchema.parse(applyScenario(prepared, {
      id: "coarse", reservations: [], unlockedCommitmentIds: [], estimateChanges: [],
      intentionChanges: [], projectChanges: [{ projectId: "essay", projectEffortMinutes: 180 }],
    }));
    const response = await solvePlanningRequest(planningRequestSchema.parse({
      ...coarse,
      negotiationQueries: [{
        id: "max", kind: "maximum-project-effort", scope: "baseline",
        projectId: "essay", maximumEffortMinutes: 300, assurance: "deadline-only",
      }, {
        id: "window", kind: "minimum-project-work-in-window", scope: "baseline",
        projectId: "essay", start: 0, end: 480, assurance: "deadline-only",
      }, {
        id: "start", kind: "latest-safe-project-start", scope: "baseline",
        projectId: "essay", earliestStart: 0, latestStart: 450,
      }, {
        id: "deadline", kind: "earliest-feasible-project-deadline", scope: "baseline",
        projectId: "essay", earliestDeadline: 15, latestDeadline: 480,
        assurance: "deadline-only",
      }],
    }));
    expect(response.negotiationResults).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: "max", maximumEffortMinutes: 300 }),
      expect.objectContaining({ id: "window", minimumRequiredMinutes: 180 }),
      expect.objectContaining({ id: "start", latestStart: 270 }),
      expect.objectContaining({ id: "deadline", earliestDeadline: 180 }),
    ]));
  }, 30_000);

  test("returns a deterministic cardinality-minimal project defer set", async () => {
    const request = await fixture("sat");
    const essay = { ...request.projects[0]!, projectEffortMinutes: 300,
      explicitEffortMinutes: 300, remainingExplicitEffortMinutes: 300 };
    const book = { ...essay, id: "book", evidence: { sourceId: "org:book", kind: "project" } };
    const essayTask = { ...request.tasks[0]!, durationMinutes: 300, prerequisiteIds: [] };
    const bookTask = { ...essayTask, id: "book-task", projectId: "book",
      evidence: { sourceId: "org:book-task", kind: "task" } };
    const queryRequest = planningRequestSchema.parse({
      ...request, tasks: [essayTask, bookTask], projects: [essay, book],
      busy: [], reserve: [], intentions: [],
      negotiationQueries: [{ id: "defer", kind: "minimal-project-defer-set",
        scope: "baseline", candidateProjectIds: ["essay", "book"],
        assurance: "deadline-only" }],
    });
    const first = await solvePlanningRequest(queryRequest);
    const second = await solvePlanningRequest(queryRequest);
    expect(first.negotiationResults[0]).toEqual(expect.objectContaining({
      feasibility: "PROVEN FEASIBLE",
      candidateProjectIds: ["book", "essay"],
      deferredProjectIds: ["book"],
      conflictProjectIds: ["book", "essay"],
    }));
    expect(second.negotiationResults).toEqual(first.negotiationResults);
  }, 30_000);

  test("proves the maximum deadline-only discretionary duration", async () => {
    const request = await fixture("sat");
    const queryRequest = planningRequestSchema.parse({
      ...request,
      busy: [],
      negotiationQueries: [{
        id: "gaming",
        kind: "maximum-deadline-only-discretionary-duration",
        scope: "baseline",
        start: 60,
        maximumEnd: 540,
      }],
    });
    const response = await solvePlanningRequest(queryRequest);
    expect(response.negotiationResults).toEqual([expect.objectContaining({
      id: "gaming",
      feasibility: "PROVEN FEASIBLE",
      maximumDurationMinutes: 270,
    })]);

    const beyondMaximum = await solvePlanningRequest(planningRequestSchema.parse({
      ...queryRequest,
      negotiationQueries: [],
      scenario: {
        id: "gaming-beyond-maximum",
        reservations: [{
          id: "gaming",
          start: 60,
          end: 345,
          kind: "scenario-reservation",
        }],
        unlockedCommitmentIds: [],
        estimateChanges: [],
        intentionChanges: [],
      },
    }));
    expect(beyondMaximum.scenario?.feasibility).toBe("PROVEN INFEASIBLE");
  }, 30_000);

  test("respects the existing scenario when querying scenario capacity", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest(planningRequestSchema.parse({
      ...request,
      busy: [],
      scenario: {
        id: "late-reservation",
        reservations: [{
          id: "late-busy",
          start: 420,
          end: 480,
          kind: "scenario-reservation",
        }],
        unlockedCommitmentIds: [],
        estimateChanges: [],
        intentionChanges: [],
      },
      negotiationQueries: [{
        id: "gaming",
        kind: "maximum-deadline-only-discretionary-duration",
        scope: "scenario",
        start: 60,
        maximumEnd: 420,
      }],
    }));
    expect(response.negotiationResults[0]).toEqual(expect.objectContaining({
      feasibility: "PROVEN FEASIBLE",
      maximumDurationMinutes: 210,
    }));
  }, 30_000);

  test("returns no optimistic answer when the query budget is zero", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest(planningRequestSchema.parse({
      ...request,
      timeoutMs: 0,
      negotiationQueries: [{
        id: "gaming",
        kind: "maximum-deadline-only-discretionary-duration",
        scope: "baseline",
        start: 60,
        maximumEnd: 540,
      }],
    }));
    expect(response.negotiationResults[0]).toEqual(expect.objectContaining({
      feasibility: "UNKNOWN",
      maximumDurationMinutes: null,
    }));
  });

  test("shares a small query budget between zero check and probes", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest(planningRequestSchema.parse({
      ...request,
      timeoutMs: 1,
      negotiationQueries: [{
        id: "gaming",
        kind: "maximum-deadline-only-discretionary-duration",
        scope: "baseline",
        start: 60,
        maximumEnd: 540,
      }],
    }));
    expect(response.negotiationResults[0]).toEqual(expect.objectContaining({
      feasibility: "UNKNOWN",
      maximumDurationMinutes: null,
    }));
  });

  test("handles zero and fully feasible quantized maxima", async () => {
    const request = await fixture("sat");
    const emptyRequest = {
      ...request,
      tasks: [],
      projects: [],
      busy: [],
      reserve: [],
      intentions: [],
      inputAssumptions: ["Durations are user estimates."],
    };
    const full = await solvePlanningRequest(planningRequestSchema.parse({
      ...emptyRequest,
      negotiationQueries: [{
        id: "short-break",
        kind: "maximum-deadline-only-discretionary-duration",
        scope: "baseline",
        start: 60,
        maximumEnd: 89,
      }],
    }));
    expect(full.negotiationResults[0]).toEqual(expect.objectContaining({
      maximumDurationMinutes: 15,
      assumptions: ["Durations are user estimates."],
    }));

    const blocked = await solvePlanningRequest(planningRequestSchema.parse({
      ...emptyRequest,
      busy: [{ id: "appointment", start: 60, end: 75, kind: "calendar" }],
      negotiationQueries: [{
        id: "blocked-break",
        kind: "maximum-deadline-only-discretionary-duration",
        scope: "baseline",
        start: 60,
        maximumEnd: 89,
      }],
    }));
    expect(blocked.negotiationResults[0]).toEqual(expect.objectContaining({
      feasibility: "PROVEN FEASIBLE",
      maximumDurationMinutes: 0,
    }));
  });

  test("is deterministic across repeated query runs", async () => {
    const request = planningRequestSchema.parse({
      ...await fixture("sat"),
      busy: [],
      negotiationQueries: [{
        id: "gaming",
        kind: "maximum-deadline-only-discretionary-duration",
        scope: "baseline",
        start: 60,
        maximumEnd: 540,
      }],
    });
    expect(await solvePlanningRequest(request)).toEqual(await solvePlanningRequest(request));
  }, 30_000);

  test("supports safe maximum, required-window, latest-start, and unlock-set queries", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest(planningRequestSchema.parse({
      ...request,
      busy: [],
      negotiationQueries: [{
        id: "safe-break", kind: "maximum-safe-discretionary-duration",
        scope: "baseline", start: 60, maximumEnd: 540,
      }, {
        id: "required", kind: "minimum-required-work-in-window",
        scope: "baseline", start: 60, end: 480, assurance: "deadline-only",
      }, {
        id: "latest", kind: "latest-safe-discretionary-start",
        scope: "baseline", durationMinutes: 30, earliestStart: 60, latestEnd: 540,
      }],
    }));
    expect(response.negotiationResults).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: "safe-break", feasibility: "PROVEN FEASIBLE",
        maximumDurationMinutes: 240 }),
      expect.objectContaining({ id: "required", feasibility: "PROVEN FEASIBLE",
        minimumRequiredMinutes: 150 }),
      expect.objectContaining({ id: "latest", feasibility: "PROVEN FEASIBLE",
        latestStart: expect.any(Number) }),
    ]));

    const unsat = await fixture("unsat");
    const unlock = await solvePlanningRequest(planningRequestSchema.parse({
      ...unsat,
      negotiationQueries: [{
        id: "unlock", kind: "minimal-commitment-unlock-set", scope: "baseline",
        candidateCommitmentIds: ["fixed-task"], assurance: "deadline-only",
      }],
    }));
    expect(unlock.negotiationResults[0]).toEqual(expect.objectContaining({
      feasibility: "PROVEN FEASIBLE",
      unlockedCommitmentIds: ["fixed-task"],
    }));
  }, 30_000);

  test("latest-start never treats a reservation overlapping busy time as feasible", async () => {
    const request = await fixture("sat");
    const response = await solvePlanningRequest(planningRequestSchema.parse({
      ...request,
      tasks: [],
      projects: [],
      reserve: [],
      intentions: [],
      busy: [{ id: "appointment", start: 60, end: 90, kind: "calendar" }],
      negotiationQueries: [{
        id: "blocked-latest",
        kind: "latest-safe-discretionary-start",
        scope: "baseline",
        durationMinutes: 30,
        earliestStart: 60,
        latestEnd: 90,
      }],
    }));
    expect(response.negotiationResults[0]).toEqual(expect.objectContaining({
      feasibility: "PROVEN INFEASIBLE",
      latestStart: null,
    }));
  });
});
