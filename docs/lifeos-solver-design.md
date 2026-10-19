# LifeOS Solver And Intentions Design

Status: **implemented with a guarded acceptance boundary**. Ordinary analysis,
reports, scenarios, negotiations, candidate generation, and candidate edits are
read-only. Only explicit complete candidate acceptance or bounded restore may
replace the machine-owned future plan in `planning.org`.

## Goal And Boundary

The solver answers whether known commitments fit, how safety and resilience
change under a counterfactual, and which quantitative alternatives remain. It
does not silently weaken deadlines and never writes Org or Calendar data. Emacs
owns the separately confirmed, preflighted accepted-plan transaction.

```text
Org/calendar -> Emacs normalization and UI -> versioned JSON
             -> TypeScript + Z3 -> versioned JSON -> Emacs report
```

Elisp owns Org parsing, configuration selection, restricted selectors, source
markers, process lifecycle, and UI. TypeScript owns schemas, constraints,
optimization, proof outcomes, core processing, scenarios, stress, and
negotiation. No Python is used.

The visible heuristic remains in place as a shadow comparison and fallback.

## Planning Precedence

1. Physical feasibility: availability, no overlap, calendar, travel, sleep,
   release times, and scenario reservations.
2. Commitments: mandatory closure, fixed starts, dependencies, and deadlines.
3. Safety: project/default deadline buffers and distributed reserve.
4. Intentions: minimum/maximum preference violations, target deviation, optional
   utility, slack/stability, and deterministic tie-breaking.

Intentions never justify a deadline violation. A task can credit every matching
intention without duplicating physical capacity.

## Normalized Model

Tasks carry stable task/project IDs, quantized remaining duration or explicit
unknown, mode, effective deadline, optional release time, prerequisites, fixed
and preferred starts, state, priority, impact, mandatory status, unresolved
waiting status, and source evidence.

Mandatory work is any active deadline or fixed-start task plus transitive active
prerequisites. Undated work is optional. Invalid optional work and unresolved
optional waiting are omitted with disclosed assumptions; equivalent mandatory
conditions yield `UNKNOWN`.

The horizon starts at the next 15-minute quantum, covers at least four weeks,
and extends past every known effective deadline/fixed commitment. Calendar and
availability coverage must reach it.

Projects carry stable ID, deadline, commitment, definition status, total and
explicit effort, active explicit remaining effort, virtual effort, default work
mode, planning chunk, confidence, diagnostics, and source evidence.
`PROJECT_EFFORT` is a total envelope:

```text
virtual effort = max(PROJECT_EFFORT - all executable descendant EFFORT, 0)
```

The subtraction includes completed tasks. Positive residual becomes stable,
mandatory virtual chunks no larger than `PLANNING_CHUNK`; a smaller final chunk
preserves the exact residual. Virtual work inherits project deadline, mode,
confidence, and evidence, participates in normal constraints and verification,
and never becomes an Org heading. Explicit over-allocation remains demand and
makes the project `INCOMPLETE`.

Project definition is `INCOMPLETE` for invalid metadata/accounting or unresolved
active descendants, `COARSE` for valid positive virtual effort, and `DETAILED`
for valid zero-virtual work. This dimension never substitutes for proof.

## Selector-Only Intentions

An exact `Name | Min | Target | Max | Selector` table defines independent weekly
preferences. Bounds are optional and current-week direct clocks count as
actuals. Restricted selectors are evaluated by Elisp and TypeScript receives
matched task IDs plus evidence.

Implemented primitives are `tag`, `project-tag`, `project-id`, `prop`,
`project-prop`, `work-mode`, `calendar-role`, and `source task`; `and`, `or`, and
`not` recurse over either task or calendar source evidence. Task primitives see
explicit task and project evidence, virtual work uses owning-project evidence,
and calendar roles see imported events. Reader evaluation is disabled.

One work item can credit multiple rows while consuming capacity once. Matching
timed calendar events count; all-day events, generated travel, and remote setup
do not. A matching weekly table replaces recurring Intentions as a whole. With
no table, work remains schedulable and no allocation targets are generated.

## Sleep, Travel, Reserve, And Stress

Each modeled night receives one contiguous minimum sleep interval in its
configured envelope. It cannot overlap work or busy time.

Every busy calendar event remains fixed. Remote attendance adds pre-event setup.
In-person travel uses per-event `TRAVEL_BEFORE`/`TRAVEL_AFTER`, then a normalized
event-type default, then the conservative unknown-location default. Missing
attendance is treated as unknown/in-person and disclosed.

Safety places daily and Monday-anchored weekly reserve chunks inside usable
availability and enforces default or project deadline buffers. Reserve is not
mere wall-clock slack.

Implemented stress profiles independently test:

- a configured percentage increase to known remaining estimates;
- loss of the largest free Deep window;
- an unexpected appointment in the earliest suitable free window.

Estimate percentages apply after explicit estimate replacements and round up to
the scheduling quantum. Invalid/unplaceable stress profiles are omitted with an
assumption because they classify resilience rather than hard feasibility.

## Scenarios

A scenario is an ephemeral, composable delta over baseline:

- add busy reservations;
- replace task estimates;
- apply percentage estimate multipliers in protocol-generated stress profiles;
- replace selected intention bounds;
- unlock selected fixed-start commitments;
- change project total effort, deadline, commitment, default work mode, planning
  chunk, or estimate confidence.

Unlocking removes only fixed-start equality. Duration, mandatory status,
release, dependency, availability, and deadline constraints remain. Scenario
optimization prefers baseline starts. Results compare moved, added, and dropped
tasks; safety/resilience transitions; start and intention deltas; reserve
deltas; and stress transitions.

Project changes apply before inherited deadlines and virtual chunks are derived.
No scenario is persisted and there is no acceptance/writeback operation.

## Negotiation

All five read-only baseline/scenario queries are implemented:

1. Maximum fixed-start discretionary duration preserving deadlines.
2. Maximum fixed-start discretionary duration preserving configured safety.
3. Minimum task work required inside a window for deadline-only or safe
   assurance.
4. Latest quantum-aligned start for a fixed discretionary duration while safe.
5. Minimum-cardinality subset of selected fixed commitments to unlock for
   deadline-only or safe feasibility.

Five project-scoped queries use the same bounded proof discipline:

1. Maximum aligned project effort preserving deadline-only or safe assurance.
2. Minimum project-owned work required in a window for the selected assurance.
3. Latest safe project start inside an explicit search range.
4. Earliest feasible project deadline inside a range for the selected assurance.
5. Deterministic cardinality-minimal project defer set from explicit candidates.

Queries have bounded searches, divide their timeout across checks, reject
invalid scenario scope, and return no numeric answer after any unknown proof.
Exact request/result semantics are in
[`lifeos-solver-protocol.md`](lifeos-solver-protocol.md).

## Assurance And Explanation

| Dimension | Implemented meaning |
|---|---|
| `PROVEN FEASIBLE` | A verified witness satisfies known hard constraints |
| `PROVEN INFEASIBLE` | Z3 proves no witness under the named assumptions |
| `UNKNOWN` | Input, coverage, timeout, optimization, or verification prevents proof |
| `SAFE` | Buffers and reserve fit in addition to hard deadlines |
| `TIGHT` | Deadlines fit but safety constraints do not |
| `RESILIENT` | Every configured stress profile is feasible |
| `FRAGILE` | At least one configured stress profile is infeasible |

Each definition-ready committed project is solved in isolation with its full
prerequisite closure, global physical constraints, and unrelated fixed
commitments, but without unrelated flexible project work. The portfolio solve
includes every definition-ready committed project. An incomplete committed
project keeps portfolio definition incomplete even when that modeled subset is
feasible.

A feasible coarse isolated result is `CAPACITY FEASIBLE`, conditional on total
effort, confidence, mode, and contiguous chunk size. It proves no unknown task
structure. `STRUCTURALLY FEASIBLE` is reserved for a feasible detailed valid
graph. Project definition, isolated feasibility, and portfolio status remain
separate; UNSAT core membership means conflict involvement, not unique blame.

Hard constraints are named and map to stable sources. UNSAT cores are reduced by
a deterministic deletion pass within the request timeout; if shrinking times
out, the sound non-minimal result is labeled. Conflicts can carry actionable
relaxations. Feasible models are checked independently before serialization.

The report exposes assumptions, defaults, coverage evidence, unlocked
commitments, local-time placements, deadline and safety margins, intention
outcomes, conflicts, relaxations, stress, query answers, comparisons, and
heuristic discrepancies.

## Determinism And Protocol

Z3 seed is zero, optimization is lexicographic, task tie-breaking is stable by
ID/start, and all movable values use 15-minute units. Version, request ID, and
protocol accompany every response. The strict boundary is
`lifeos-planning/v3`; project inventory, virtual-work evidence, structured
task/project conflict ownership, portfolio results, project scenario deltas,
and project negotiations remain required concepts. V3 adds exact candidate
identity, hard user placements, exclusions, task/project-capacity estimate
overrides, current-plan seed preferences, stable task/project attribution,
placement and omission rationale, and independently recomputable planning
evidence. Candidate seed stability precedes deadline slack, while ordinary and
scenario optimization retain the prior objective order. Existing task release
constraints remain hard and are not replaced by candidate behavior.

## Verification And Rollout

Implemented coverage includes strict schemas/references/scenarios, semantic
SAT/UNSAT goldens, timeout and unknown handling, release/fixed/unlock behavior,
intentions, sleep, travel, reserve, stress, all query kinds and caps,
deterministic reruns, generated property checks, independent verification,
Elisp normalization/process/report/scenario tests, and no-mutation tests. CI
runs ERT, TypeScript check/build, Vitest, and moderate-level npm audit.

The TypeScript suite independently tampers with candidate identity, source
attribution, rationale, and planning evidence in addition to checking exact
placement conflicts, exclusions, draft estimates, seed stability, and coarse
capacity attribution.

The implementation does not imply personal policy approval. Sleep, buffers,
reserve, travel, and stress values must be reviewed by the user. The heuristic
remains the visible fallback; solver placements affect the current flexible plan
only when the user reviews and explicitly accepts a complete current candidate.
