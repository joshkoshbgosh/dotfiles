# LifeOS Planning Protocol v3

`lifeos-planning/v3` is the read-only JSON boundary between Emacs and the
TypeScript/Z3 solver. `lifeos-solver/src/protocol.ts` is the executable schema.

## Transport And Time

- One UTF-8 JSON request is read from stdin; one JSON response plus newline is
  written to stdout; diagnostics use stderr.
- Exit `0` means a schema-valid response, `2` an invalid request, and another
  nonzero value a process failure.
- Every response carries protocol version, solver version, and normalized
  request ID. Candidate responses additionally echo candidate ID, revision,
  captured input fingerprint, and that same normalized request ID.
- Time is integer Unix epoch minutes and intervals are half-open `[start,end)`.
- Scheduling quantum is exactly 15 minutes. Movable work is contiguous and
  quantum-aligned; exact fixed starts are preserved.
- `timeoutMs` is `0..300000`. Zero returns `UNKNOWN` without a safety claim.

For ordinary portfolio analysis, Elisp cancels the previous solver process,
rejects stale request IDs, scales the process timeout by worst-case solve/query
stages, and retains the last good response after failure. Candidate analysis
coalesces unsent edits but may leave older checks in flight; the candidate ID,
revision, input fingerprint, request ID, and independent verification gates reject
out-of-order or mismatched responses.

## Request

The request contains horizon/coverage, timeout and quantum, default safety
buffer, hard/safety issues, assumptions, canonical projects and tasks,
availability, busy calendar/travel blocks, sleep, reserve, selected intentions,
stress profiles, an optional scenario, and negotiation queries.

`candidate` is null for ordinary analysis. A candidate request contains a
stable `candidateId`, nonnegative monotonic `revision`,
`capturedInputFingerprint`, exact task starts, task or `PROJECT_CAPACITY`
exclusions, candidate-only task or capacity estimate overrides, and
source-attributed current-plan seed intervals. Exact placements apply only to
flexible explicit tasks. Capacity demand is attributed to its project and never
presented as a concrete source task.

Each project includes stable `id`, nullable deadline and safety buffer, source
evidence, `definitionStatus`, `commitment`, total/explicit/remaining-explicit/
virtual effort, nullable coarse metadata, and diagnostics. Definition-ready
projects require deadline and total effort. `COARSE` requires positive virtual
effort, default mode, planning chunk, and confidence; `DETAILED` requires zero
virtual effort.

Project effort is an envelope, not additive demand. `explicitEffortMinutes`
includes the declared effort of completed executable descendants;
`virtualEffortMinutes` is the nonnegative difference between total and explicit
effort. Active explicit remaining work retains direct-clock balance semantics.
Virtual residual is split into deterministic project-owned chunks no larger
than `planningChunkMinutes`, with a smaller final chunk when needed.

Each task has nullable `projectId`, duration and deadline, a `deadlineSource`,
release/fixed/preferred starts, prerequisites, scheduling metadata, mandatory
and waiting flags, evidence, and `workType`. A virtual task additionally carries
project ID, ordinal, chunk count, confidence, and project evidence. It must be
mandatory, flexible, dependency-free, and owned by the same project.

Selectors do not cross the wire. Emacs evaluates the restricted, source-aware
selector language recursively over explicit/virtual task-project evidence and
calendar-role evidence, then sends each intention's `matchedTaskIds`, current
actual minutes, and match evidence. Rows may overlap; physical tasks are still
placed only once. No selected Intentions table produces an empty intention list
plus an explicit no-target assumption.

Task `releaseTime` is nullable. When present, selected work starts at or after
it. Mandatory unknown duration or unresolved waiting is a preflight `UNKNOWN`;
optional unresolved work is not selected. Mandatory closure includes deadline
or fixed-start tasks and all transitive prerequisites.

`estimateMultipliers[].percentage` is a non-negative percentage, not a decimal
factor. Scenario application first performs an explicit estimate replacement,
then computes:

```text
ceil((duration * (1 + percentage / 100)) / quantum) * quantum
```

## Strict Validation

IDs are unique within each collection and negotiation queries. Task projects,
prerequisites, intention matches, scenario changes, unlocks, and query
candidates must reference existing compatible records; self-prerequisites and
duplicate references are rejected.

All project effort and planning chunk values are 15-minute aligned. A
definition-ready project cannot allocate more explicit effort than its total.
Virtual task ordinals cannot exceed chunk count, and explicit tasks cannot carry
virtual-work evidence.

Candidate edit references are unique by demand, known, and kind-compatible.
Exact starts and every seed boundary are aligned; exact and seed intervals fit
the replacement horizon. Excluded demand cannot simultaneously be exact,
overridden, or seeded. Task seeds match the candidate-only task duration.
Project-capacity seeds, sorted by interval, match deterministic post-override
virtual chunk durations. Candidate objects and their edit records are strict;
unknown fields are rejected.

Scenario and stress-profile scenarios use the same validation:

- reservation IDs are unique and do not duplicate busy IDs;
- reservations have `scenario-reservation` kind, fit the horizon, and have
  quantum-aligned duration;
- unlock IDs refer to fixed-start tasks;
- estimate replacement and multiplier task IDs are unique and known;
- replacement durations are positive and quantum-aligned;
- intention change IDs are unique and known, and merged bounds satisfy
  `minimum <= target <= maximum` where present;
- project changes are unique and known; effort/chunk changes are positive and
  quantum-aligned, and fields are limited to total effort, deadline, commitment,
  default mode, planning chunk, and confidence.

Every query interval is nonempty and inside the horizon. Scenario scope requires
a scenario. Latest-start duration is positive and quantum-aligned. Unlock
candidates are unique fixed-start tasks. Project query IDs and defer candidates
must reference known projects; maximum project effort is quantum-aligned.

## Solving

Deadline feasibility enforces horizon, availability/mode, physical busy blocks,
no overlap, sleep, release times, mandatory selection, prerequisites, fixed
starts unless unlocked, and actual deadlines. Safety solving additionally uses
project/default deadline buffers and reserve blocks in usable availability.

After feasibility, optimization is lexicographic:

1. minimize total intention minimum shortfall and maximum excess;
2. minimize total target deviation;
3. maximize optional utility (`A/B/C/D = 40/30/20/10`, plus
   `High/Medium/Low = 3/2/1`);
4. maximize summed deadline slack;
5. minimize movement from preferred starts;
6. minimize each selected start in stable task-ID order.

For candidate solves only, current-plan seed movement is minimized before
deadline slack, so a feasible seed remains stable. An exact user placement is a
hard selected equality and is never softened by that objective. If it conflicts,
the solve is infeasible and reports the exact-placement constraint rather than
moving the task. Candidate task and project-capacity estimates are applied only
to the normalized in-memory solve. Exclusions remove only candidate demand.

Stress profiles rerun deadline-only feasibility independently. Any infeasible
stress yields `FRAGILE`; all feasible yields `RESILIENT`; any `UNKNOWN` leaves
resilience null.

For each definition-ready committed project, isolated solving includes its
explicit and virtual tasks, transitive prerequisites, all physical constraints,
and unrelated fixed commitments while excluding unrelated flexible work. The
portfolio scope contains all definition-ready committed demand. Incomplete and
uncommitted projects are excluded and disclosed; any incomplete committed
project makes portfolio definition `INCOMPLETE` even when the modeled subset is
feasible.

## Query Union

Every query has unique `id`, `scope: baseline | scenario`, and a discriminating
`kind`. Scenario scope applies all existing scenario reservations, estimate and
intention and project changes, and unlocks before the query.

### Maximum Deadline-Only Discretionary Duration

Request:

```text
kind, scope, start, maximumEnd
```

At fixed `start`, find the largest quantum duration through `maximumEnd` that
preserves hard deadline feasibility. Safety buffers and reserve are excluded.
The solver proves zero-duration feasibility, tests the full range, then performs
bounded binary search. A physical overlap with existing busy time is infeasible.

Result includes `feasibility`, nullable `maximumDurationMinutes`, `testedStart`,
`testedMaximumEnd`, and assumptions.

### Maximum Safe Discretionary Duration

The request/result shape and search match the deadline-only maximum, but every
probe includes configured deadline buffers and reserve. Missing safety
configuration returns `UNKNOWN`, not a deadline-only substitute.

### Minimum Required Work In Window

Request:

```text
kind, scope, start, end, assurance: deadline-only | safe
```

Minimize the sum of placed task minutes overlapping `[start,end)` while
preserving the requested assurance. The returned witness is independently
checked, its overlap is recomputed, and a separate solver proves that no lower
value is feasible.

Result includes nullable `minimumRequiredMinutes`, tested bounds, assurance,
feasibility, and assumptions.

### Latest Safe Discretionary Start

Request:

```text
kind, scope, durationMinutes, earliestStart, latestEnd
```

Search quantum-aligned starts backward from the latest possible start for the
fixed duration. This query is always safe, not deadline-only. It checks at most
4096 candidate starts. Existing busy overlap is never treated as feasible.

Result includes nullable epoch-minute `latestStart`, tested duration/bounds,
feasibility, and assumptions.

### Minimal Commitment Unlock Set

Request:

```text
kind, scope, candidateCommitmentIds, assurance: deadline-only | safe
```

Sort candidates by ID and test subsets by increasing cardinality and stable
combination order. Existing scenario unlocks remain active; the result reports
only the additional selected candidate subset. At most 16 candidates are
accepted, for at most `2^n` checks.

Result includes sorted candidates, nullable `unlockedCommitmentIds`, assurance,
feasibility, and assumptions.

## Project Query Union

These five queries also carry unique `id`, `scope: baseline | scenario`, and
their discriminating `kind`. Except for latest safe start, they include
`assurance: deadline-only | safe`.

### Maximum Project Effort

`maximum-project-effort` supplies `projectId` and positive aligned
`maximumEffortMinutes`. It finds the largest aligned total envelope up to that
cap that preserves the selected assurance. The nullable answer is
`maximumEffortMinutes`; `testedMaximumEffortMinutes` records the cap.

### Minimum Project Work In Window

`minimum-project-work-in-window` supplies `projectId`, `start`, `end`, and
assurance. It minimizes project-owned placed minutes overlapping the window,
then verifies the witness and proves no lower value. The nullable answer is
`minimumRequiredMinutes`.

### Latest Safe Project Start

`latest-safe-project-start` supplies `projectId`, `earliestStart`, and
`latestStart`. It searches aligned start bounds while preserving configured
safety. The nullable answer is `latestStart`.

### Earliest Feasible Project Deadline

`earliest-feasible-project-deadline` supplies `projectId`,
`earliestDeadline`, `latestDeadline`, and assurance. It searches for the
earliest aligned bound in that horizon that preserves the requested proof. The nullable
answer is `earliestDeadline`.

### Minimal Project Defer Set

`minimal-project-defer-set` supplies unique explicit `candidateProjectIds` and
assurance. Candidates are sorted and subsets are tested by increasing
cardinality and stable combination order. The nullable `deferredProjectIds` is
one deterministic cardinality-minimal set, not a unique organizational
recommendation; `conflictProjectIds` reports current conflict involvement.

## Query Budgets And Unknown

Each query receives the request timeout as its total search budget and divides
it deterministically across its maximum checks. Maximum queries use a zero
check, full-range check, and logarithmic probes. Minimum-work splits budget
between optimization and lower-bound verification. Latest-start and unlock-set
queries divide across exhaustive bounded checks. Project boundary searches use
aligned bounded probes; project defer search is candidate-bounded subset
minimization.

If the budget cannot allocate at least 1 ms per required check, any probe is
`UNKNOWN`, optimization/verification is unknown, or safety inputs are missing,
the query returns `UNKNOWN` and its numeric/set answer is null. No optimistic
partial bound is returned.

## Results

A solve result contains:

- feasibility, nullable safety and resilience;
- task, sleep, and reserve placements;
- intention allocation, minimum shortfall, target deviation, and maximum excess;
- per-task deadline, completion, hard-deadline margin, safety-buffer amount, and
  safety margin;
- mapped conflicts and optional actionable relaxation;
- assumptions, sorted unlocked commitment IDs, and stress outcomes.

Candidate placements also contain `demandKind`, stable task/project `sourceId`,
nullable project confidence, and one rationale: fixed commitment, exact user
placement, kept seed, planner-moved seed, or newly solver-selected work. Virtual
chunk IDs remain internal task IDs; `PROJECT_CAPACITY` plus the project source is
the workbench attribution.

Candidate results include explicit `user-excluded`, `solver-omitted`, or
`unresolved-input` omissions with source, effort, deadline, confidence, and
project attribution. `candidateEvidence` repeats the exact response identity and
summarizes exact, excluded, overridden, exact kept/moved/omitted seed counts and sources plus
deadline, safety, intention, estimate-confidence, and capacity status and
placed/omitted capacity minutes.

Each project result keeps these dimensions separate:

- definition: `INCOMPLETE`, `COARSE`, or `DETAILED`;
- isolated feasibility: `FEASIBLE`, `INFEASIBLE`, `UNKNOWN`, or `UNCOMMITTED`;
- proof kind: nullable `CAPACITY FEASIBLE` or `STRUCTURALLY FEASIBLE`;
- portfolio status: `FITS`, `TIGHT`, `CONFLICT-INVOLVED`, `UNKNOWN`, or
  `UNCOMMITTED`.

It also includes the isolated solve, borrowed prerequisite task/project IDs,
minimum hard and safety margins, and structured conflict task/project IDs. A
portfolio result includes `COMPLETE | INCOMPLETE` definition, feasibility,
safety, modeled and excluded project IDs, `modeledSubset`, the global solve, and
all project results. Core membership means conflict involvement, not unique
causation.

Relaxation types are `unlock-commitment`, `add-compatible-availability`,
`provide-duration-estimate`, `model-release-condition`, `adjust-safety-policy`,
`resolve-input-assumption`, and `move-after-release`.

A scenario response also includes interpretation, moved/added/dropped task IDs,
safety and resilience transitions, task-start deltas, intention-allocation
deltas, reserve count/minute delta, and per-stress feasibility transitions.
It additionally returns baseline/scenario portfolios and project deltas for
definition, effort, deadline, commitment, isolated feasibility, and portfolio
status. Project changes are applied before inherited task deadlines and virtual
chunks are recomputed.

## Proof Hygiene

Every hard expression has a named assumption mapped to stable constraint/source
IDs, kind, and message. For UNSAT, a deterministic deletion pass attempts to
shrink the core within the remaining request budget. If shrinking times out,
the returned core remains sound and an assumption says it may be non-minimal.
Raw clauses are not the user-facing result.

Every feasible ordinary or query witness is independently checked for required
placements, identity uniqueness, duration/kind, horizon/grid, release,
availability, busy overlap, fixed starts, deadlines/buffers, dependencies,
task overlap, exact sleep/reserve sets, envelopes, usable reserve availability,
and protected-block overlap. Verification failure becomes `UNKNOWN`.

Candidate response verification first requires exact request ID, candidate ID,
revision, captured fingerprint, and normalized-request-ID identity. It reapplies
candidate edits independently, then checks exact starts, post-override duration,
exclusion, source/project attribution, placement and omission rationale,
seed conversion, and every planning-evidence summary. Any mismatch prevents the
response from becoming current evidence.

## Read-Only Boundary

Protocol v3 contains no acceptance or writeback operation. Emacs alone reads Org
and calendar sources; TypeScript receives normalized JSON and never opens those
files. Explicit and virtual placements, isolated/portfolio proofs, scenario
project changes, deferrals, and all negotiation answers are ephemeral. Virtual
tasks have no Org markers. A newer request ID invalidates older asynchronous
responses. Candidate edits and current-plan seeds are transient normalized JSON,
not write instructions. Failure retains the last internally consistent result rather
than mutating source data.
