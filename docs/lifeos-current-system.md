# LifeOS Current System

This document describes implemented behavior. Org under `~/Work/lifeos/` is
authoritative; Supertag indexes it. Analysis is read-only except for explicit
guarded complete schedule-candidate acceptance and bounded previous-plan restore.

## Task And Graph Model

An operational task is a leaf active TODO heading marked `#task`.

| Field | Meaning |
|---|---|
| `ID` | Stable identity and dependency target |
| Priority `A`-`D` | Ordering and optional solver utility |
| `EFFORT` | Expected total effort at completion |
| `ORIGINAL_EFFORT` | First accepted estimate |
| `IMPACT` | `High`, `Medium`, or `Low` |
| `WORK_MODE` | `Deep`, `Shallow`, `Errand`, or `Social` |
| timed `SCHEDULED` | Fixed start |
| `DEADLINE` | Hard completion limit at the end of the local date |
| `WAIT_UNTIL` | Future solver release time for `WAITING` work |
| `depends-on` | Prerequisite ID |

`TODO` and `NEXT` are allocatable. `WAITING` requires a dependency,
`WAIT_UNTIL`, or `WAITING_FOR`; mandatory waiting without a modeled future
release makes assurance unknown. `SOMEDAY` is excluded. Completed states are
historical.

Hierarchy means composition and the nearest `#project` ancestor owns a task.
Dependencies mean execution order. Validation, graph analysis, summaries, and
both planners reject or exclude aggregate `#task` headings. Project `LEFT`
contains only known positive balances from executable leaves plus their unknown
count.

Direct clocks determine remaining work:

```text
remaining = EFFORT - direct clocked minutes
```

Zero or negative balance is a review finding and unknown future duration until
re-estimated, not negative work. `my/lifeos-set-remaining-effort` preserves
`ORIGINAL_EFFORT` and appends an `EPISODE`/`CORRECTION` record to a task-local,
append-only `LIFEOS_EFFORT` drawer. Anchored accounting counts only clocks after
that correction; an `EFFORT` rewrite without a correction record remains
legacy/unanchored.

## Capture And Diagnostics

Adding textual `#task` or `#project` scaffolds an ID and the corresponding empty
planning fields after editing or before save. `my/lifeos-groom-project`, bound
to `M-; n p m`, prompts in plain language for the project deadline, total effort,
usual work mode, largest planning chunk, and confidence; users do not need to
remember Org property names. Grooming fills required values. Task findings are transient
structured overlays with Error, Review, or Conflict severity; Org text is not
changed.

`my/lifeos-next-diagnostic` and `my/lifeos-previous-diagnostic` navigate task and
project diagnostic overlays. `my/lifeos-explain-at-point` explains task findings,
cached forecast conflicts, and project metrics.

Project summaries share the debounced graph/forecast snapshot:

| Metric | Meaning |
|---|---|
| `DONE` | Completed versus non-cancelled executable descendants |
| `LEFT` | Known positive remaining work plus unknown count |
| `FIXED` | Valid active work with a timed fixed start |
| `PLAN` | Valid active work with fixed or heuristic placement |
| `UNPLACED` | Project-owned heuristic failures |
| `TIGHTNESS` | Latest heuristic slack against project deadline |

## Project Definitions

Every explicitly tagged `#project` is inventoried. Deadlines, hierarchy, and TODO
descendants never cause project inference. Executable tasks without a nearest
explicit project are listed as orphan work and are never silently moved.

A project with no TODO state, or with `TODO`, `NEXT`, or `WAITING`, is committed.
`SOMEDAY`, `DONE`, and `CANCELLED` projects remain visible but uncommitted. The
project fields are:

| Field | Meaning |
|---|---|
| `ID` | Stable project identity; required for active readiness |
| `DEADLINE` | Parseable completion limit; required for active readiness |
| `PROJECT_EFFORT` | Positive 15-minute-aligned expected total effort |
| `DEFAULT_WORK_MODE` | Work mode inherited by virtual residual work |
| `PLANNING_CHUNK` | Positive 15-minute-aligned maximum virtual chunk size |
| `ESTIMATE_CONFIDENCE` | `Low`, `Medium`, or `High` disclosure |
| `SAFETY_BUFFER` | Optional project override for the solver deadline buffer |

`PROJECT_EFFORT` is one envelope. Explicit allocation is the sum of `EFFORT`
for every executable descendant, including completed tasks. Virtual effort is
`max(PROJECT_EFFORT - explicit allocation, 0)`. Remaining demand is active
explicit remaining effort plus virtual effort. Completed estimates therefore do
not reappear, and adding an explicit task reduces virtual residual rather than
adding to the project total. If explicit allocation exceeds the envelope, all
explicit demand remains and the project is diagnosed as stale and incomplete.

Positive virtual effort requires the three coarse fields above and is divided
deterministically into chunks no larger than `PLANNING_CHUNK`, with a smaller
last chunk. Chunks inherit project ID, deadline, mode, mandatory status,
confidence, and project evidence. They have stable IDs but no Org headings or
markers.

Definition status is independent of solver proof:

- `INCOMPLETE`: required metadata or effort accounting is invalid, or active
  descendant work is unresolved/non-executable.
- `COARSE`: definition-ready with positive virtual effort.
- `DETAILED`: definition-ready with zero virtual effort and valid executable
  active descendants.

For a complete Org example in which explicit tasks replace virtual residual,
see [README.md](../README.md#coarse-to-detailed).

## Weekly Inputs

`planning.org` contains recurring defaults and optional `#week` snapshots with
exact `WEEK_START`. Availability, Intentions, and Solver configuration select a
matching weekly table when present and otherwise use recurring defaults.
Selected tables replace recurring rows as a whole; they never merge.

Intentions use the exact five-column table documented in [`README.md`](../README.md).
They are the only weekly allocation model. Supported source-aware primitives are
`tag`, `project-tag`, `project-id`, `prop`, `project-prop`, `work-mode`,
`calendar-role`, and `source task`, composed recursively with `and`, `or`, and
`not`. Task primitives inspect explicit task and owning-project evidence;
virtual work uses its owning project evidence; calendar-role inspects calendar
events. One item may credit every matching row without duplicating physical
capacity. With no selected table, work remains schedulable and reports state
that no allocation targets are configured.

The intention ledger reports independent views of remaining, current-week
direct clocks, matching timed calendar minutes, fixed placements, proposed
placements, and target remainder. Intentions are preferences below hard
feasibility and do not steer the heuristic's placement rules.

Solver configuration uses a strict complete Key/Value table. A weekly table is
not merged with recurring defaults. If no table exists, conservative defcustom
fallbacks apply; those code choices are not evidence of personal policy
approval.

## Calendar

org-gcal imports into `calendar.org` five seconds after startup and every 15
minutes. Overlapping imports are skipped. Successful changes are normalized and
saved before the shared analysis cache is invalidated. Full refresh clears sync
tokens; cancelled events are removed unattended.

- Busy timed events block their exact interval.
- Busy all-day events block the local day.
- Transparent events do not block availability.
- Timed events contribute to every matching calendar-role intention; all-day
  events contribute no allocation minutes.
- Solver assurance requires a successful fetch at most 30 minutes old and
  explicit coverage through the assurance horizon.
- `ATTENDANCE=remote` adds configured setup; `in-person` adds travel.
- `TRAVEL_BEFORE` and `TRAVEL_AFTER` override typed and unknown defaults.
- Missing attendance conservatively uses in-person unknown-location travel and
  discloses the assumption.
- Calendar-role intention actuals count event time, not generated travel/setup.

## Visible Heuristic

`my/lifeos-build-forecast` remains the visible deterministic four-week greedy
forecast:

1. Build graph-eligible active records.
2. Generate local availability and subtract busy calendar time.
3. Validate and reserve fixed timed work.
4. Order dependency-safely by rough slack, critical path, priority, impact,
   duration, and stable ID.
5. Place each flexible task in the first compatible contiguous window.
6. Return virtual placements and explicit failures.

It uses 15-minute rounded durations and does not fragment tasks. It represents
dependencies, fixed starts, availability, calendar blocking, work modes, and
effective deadlines. It does not globally optimize or model solver sleep,
travel, reserve, stress, intentions, proofs, or cores.

## Solver Shadow

After shared analysis refresh, `lifeos-solver.el` normalizes the complete model
and starts the TypeScript/Z3 process asynchronously.

- The horizon starts at the next 15-minute quantum and extends at least four
  weeks and through all known deadlines/fixed commitments.
- Mandatory work is deadline/fixed work plus its transitive prerequisites.
- Future `WAIT_UNTIL` is a hard release time.
- Availability is canonicalized; sleep is contiguous; reserve protects usable
  availability; travel and scenario reservations are physical busy intervals.
- The solver first proves deadline feasibility, then separately tests safety,
  then independently runs configured stress profiles.
- Intentions are optimized lexicographically after hard constraints.
- Returned feasible placements are independently verified.
- Infeasible results contain mapped, boundedly shrunk cores and actionable
  relaxations when available.
- Request IDs reject stale responses. A newer request cancels the older process;
  timeout or failure preserves the last good response.

The solver uses `lifeos-planning/v3`. Ordinary requests carry `candidate: null`
and responses carry `candidateIdentity: null`; adjustable schedule checks use a
revision-keyed candidate request and exact matching response identity. It proves each definition-ready committed
project in an isolated scope containing its explicit and virtual work,
transitive prerequisites, global calendar/travel/sleep/reserve constraints, and
unrelated fixed commitments, while excluding unrelated flexible project work.
It also solves all definition-ready committed projects together. Incomplete
committed projects keep portfolio definition `INCOMPLETE` even if the modeled
subset fits.

The dedicated report shows local-time placements, assumptions, deadline
margins, intention outcomes, conflicts/relaxations, stress results, unlocked
commitments, baseline/scenario comparison deltas, negotiation answers, and
heuristic discrepancies. Raw JSON is separate. Source buttons use captured
markers.

Scenarios are composable in-memory deltas: reservations, task estimate
replacements, intention changes, fixed-start unlocks, and project total effort,
deadline, commitment, work mode, chunk size, or confidence changes. Project
deltas apply before inherited deadlines and virtual work are derived. Running
or querying one never writes Org.

## Adjustable Schedule Candidates

Portfolio Review projects detailed evidence to `NEED INFO`, `DOES NOT FIT`, `AT
RISK`, or `FITS` and opens one candidate from its exact current snapshot with
`s`. The dedicated read-only workbench renders Schedule, Omissions, and
Consequences, with textual `[FIXED]`, `[KEEP]`, `[NEW]`, `[MOVED: USER]`, `[MOVED:
PLAN]`, `[CAP]`, `[EXCL]`, and `[OMIT]` provenance labels.

The transient candidate condition is `EDITING`, `CHECKING`, `CURRENT`, or
`STALE`. Exact placement, exclusion, candidate-only estimate overrides, and
latest-edit undo increment its revision without writing Org. Debounced responses
become current only when candidate ID, revision, input fingerprint, request ID,
and independent verification match. While checking, prior proof is context and
the planning status is `NEED INFO`.

The current flexible plan is one canonical machine-owned `Accepted schedule`
subtree in `planning.org`. Plan metadata records ID, source fingerprint, horizon,
and acceptance time. Direct children are source-attributed `TASK` or
`PROJECT_CAPACITY` blocks with normative start, end, and duration plus an agreeing
active Org timestamp. Coarse capacity reserves project effort but does not invent
a concrete task. Generated block IDs are not stable. Accepted records do not use
`SCHEDULED`: timed source `SCHEDULED` values and calendar events remain fixed,
while accepted blocks are flexible replaceable planning context.

Acceptance operates only on a complete `CURRENT` candidate. `FITS` receives
normal confirmation, `AT RISK` requires an additional warning confirmation, and
`NEED INFO` or `DOES NOT FIT` cannot write. Preflight reparses authoritative
input and validates identity, fingerprints, horizon, block structure, fixed
conflicts, and clean target-buffer state. The boundary preserves accepted records
ending at or before the first aligned boundary outside an in-progress block and
replaces every record beginning at or after it, including records beyond the
candidate horizon. It never splits an intersecting block.

The complete new subtree is constructed before one atomic live-buffer edit and
successful save. Failure leaves the prior plan unchanged, and source tasks,
projects, calendars, estimates, deadlines, states, and timed `SCHEDULED` values
remain outside write scope. At most one exact previous/result subtree pair is
retained for guarded restore of the latest acceptance in the current Emacs
session. Restart or subtree drift invalidates it; another acceptance replaces the
old restore point with a new pair for the latest acceptance.

`my/lifeos-solver-show-portfolio-review`, bound to `M-; n p P`, is the top-level
read-only project view. It separates commitment, definition, isolated proof, and
portfolio status; shows total, explicit remaining, virtual remaining, margins,
confidence, and next finding; and drills into metadata errors, explicit and
virtual work, borrowed prerequisites, conflicts, and assumptions. Probable
projects and orphan work have separate source-linked sections.

The five project negotiations ask for maximum project effort, minimum required
project work in a window, latest safe project start, earliest feasible project
deadline, or a deterministic cardinality-minimal defer set from explicit
candidates. They run against baseline or scenario; applicable queries select
deadline-only or safe assurance. Exact semantics are in
[`lifeos-solver-protocol.md`](lifeos-solver-protocol.md).

`my/lifeos-scheduling-review-fixture` shows the coordinator's read-only
scheduling review for the checked-in synthetic fixture: plan validity, Q1 pinned
feasibility, Q2 unpinned feasibility and the two overall results. It runs
`scripts/scheduling-review.ts`, never reads live Org, never invokes the Org write
path, and labels the output as synthetic/non-live evidence.

## Assurance Boundary

`PROVEN FEASIBLE` and `PROVEN INFEASIBLE` apply only to normalized known input.
Missing mandatory duration, malformed mandatory graph/input, unresolved
mandatory waiting, stale or short coverage, timeout, and failed model
verification produce `UNKNOWN`. Missing safety configuration leaves safety
unset. `SAFE` includes configured buffers and reserve; `TIGHT` preserves hard
deadlines but not all safety constraints. Stress results yield `RESILIENT`,
`FRAGILE`, or unset when any stress result is unknown.

A feasible `COARSE` project is `CAPACITY FEASIBLE`: it proves that explicit and
chunked virtual demand fits under the stated assumptions, not unknown ordering
or dependencies. `STRUCTURALLY FEASIBLE` is reserved for a feasible `DETAILED`
project with a valid task graph. Isolated `FEASIBLE`/`INFEASIBLE`/`UNKNOWN` and
portfolio `FITS`/`TIGHT`/`CONFLICT-INVOLVED`/`UNKNOWN` remain separate. Conflict
involvement is not unique causal blame.

The heuristic remains the visible source for current overlays and dynamic
blocks. Replacing it requires representative real-week review, understood
discrepancies, and explicit user acceptance.

## Module Map

All Emacs paths are below `config/emacs/.config/emacs/`.

| File | Responsibility |
|---|---|
| `org/lifeos-planning.el` | Schema, grooming, graph, project inventory, selectors, intention accounting, cache |
| `org/lifeos-forecast.el` | Visible read-only heuristic |
| `org/lifeos-schedule.el` | Candidate lifecycle and workbench, accepted-plan parsing, guarded acceptance, bounded restore |
| `org/lifeos-solver.el` | Protocol v3 normalization, config, async process, portfolio/scenario/query UI, reports |
| `org/lifeos-supertag.el` | Canonical tag identity and projections |
| `org/org-gcal.el` | Calendar import, freshness/coverage evidence, polling |
| `leader/general.el` | Leader bindings |
| `lifeos-solver/src/protocol.ts` | Executable wire schemas |
| `lifeos-solver/src/candidate.ts` | Candidate transformations, attribution, omissions, and evidence |
| `lifeos-solver/src/solver.ts` | Z3 constraints, optimization, cores, stress, queries |
| `lifeos-solver/src/scenario.ts` | Scenario application and estimate multipliers |
| `lifeos-solver/src/verify.ts` | Independent model verification |

## Verification

Use the commands in [`README.md`](../README.md). The 2026-10-19 verified baseline
is 167/167 ERT, 8/8 documentation ERT, and 51/51 Vitest; TypeScript check/build
pass and the moderate-or-higher npm audit reports zero vulnerabilities.
