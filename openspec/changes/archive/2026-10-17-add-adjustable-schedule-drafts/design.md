## Context

LifeOS already normalizes Org tasks, projects, calendar constraints, recurring
availability, and intentions into solver requests. Portfolio and scenario results
can contain placements, but those placements are deliberately shadow evidence:
they are read-only, tied to one request snapshot, and discarded when the next
scenario is built. The portfolio UI also exposes detailed proof vocabulary rather
than one decision-oriented status.

This change introduces one transient candidate between solving and the current
authoritative plan in Org. The candidate must remain safe while the user adjusts
it, asynchronous solver responses arrive, and source buffers change. Acceptance
is the sole exception to the existing no-write rule and replaces the complete
machine-owned future plan rather than committing individual blocks.

## Goals / Non-Goals

**Goals:**

- Maintain one active candidate future plan with simple freshness and analysis
  state.
- Support exact placement, exclusion, draft-only re-estimation, and edit undo
  without changing task or project source metadata.
- Debounce background feasibility checks while rendering edits immediately.
- Reject out-of-order analysis and prevent stale or unverified acceptance.
- Map detailed proof to `FITS`, `AT RISK`, `DOES NOT FIT`, or `NEED INFO`
  without discarding the underlying evidence.
- Persist the complete accepted future plan in a canonical, machine-owned Org
  subtree distinct from fixed commitments.
- Replace that future plan atomically after explicit review and preserve the
  previously accepted plan until replacement succeeds.
- Preserve the shadow-only boundary everywhere except explicit whole-plan
  acceptance or an immediately available guarded restore.

**Non-Goals:**

- Partially accepting a candidate or maintaining multiple simultaneous drafts.
- Splitting a concrete task into independently placed schedule segments.
- Preserving stable block identity or lineage across accepted plan generations.
- Automatically accepting solver output or changing task state, source estimates,
  deadlines, project commitments, calendar events, or timed `SCHEDULED` values.
- Treating a proposed or accepted flexible block as a fixed appointment.
- Synchronizing accepted blocks to an external calendar.
- Persisting candidates or restore history across Emacs restarts.
- Inferring execution, completion, or time tracking from accepted blocks.
- Replacing detailed solver proof, scenario comparison, or portfolio drilldowns.

## Decisions

### Model one transient candidate and one current plan

LifeOS exposes at most one active schedule candidate. It owns a candidate ID,
captured normalized-input fingerprint, monotonic revision, replacement horizon,
complete candidate placements, exclusions, draft estimate overrides, edit
history, and the latest matching feasibility result.

The live candidate condition is `EDITING`, `CHECKING`, `CURRENT`, or `STALE`:

- A local edit increments the revision, renders immediately, and enters
  `EDITING` until its debounced request is sent.
- A sent request enters `CHECKING`.
- Matching independently verified evidence enters `CURRENT`, even when its
  planning status is `AT RISK` or `DOES NOT FIT`.
- Any authoritative input change enters `STALE`.

Acceptance and discard close the candidate instead of adding terminal lifecycle
states. The accepted plan remains unchanged throughout generation and editing.
Candidate generation copies its replaceable future blocks into the candidate as
seed placements associated with their source demand. They are not also modeled
as hard occupied intervals inside that replacement solve. Outside replacement
mode, the accepted plan remains occupied flexible context for portfolio and Today
analysis. Keeping the candidate in memory avoids defining a second durable source
of truth.

Multiple drafts, partial acceptance, and successor drafts were rejected for the
initial version because they require merge, subset-closure, and concurrency
semantics without improving the primary review-adjust-accept workflow.

### Keep manipulation bounded and exact

Candidate operations append reversible edits without mutating Org:

- Place assigns a new or carried candidate task block an exact aligned start.
  Verification must either honor that interval or report the conflict; the solver
  does not silently adjust the requested placement.
- Exclude removes selected candidate task demand or a coarse project reservation
  from this candidate and keeps the omitted effort and consequences visible. It
  does not cancel or modify the source task or project.
- Re-estimate overrides total effort for candidate analysis only and acceptance
  never writes that estimate back to the source.
- Undo removes the most recent candidate edit and creates a new revision. Redo is
  not required.

Fixed commitments are visible immutable constraints. Current-plan blocks remain
visible as the authoritative baseline while their future source-attributed copies
participate in the candidate. Editing a carried copy changes only the candidate;
accepting the complete candidate supersedes all replaceable future current-plan
blocks within its horizon. There is no direct accepted-record edit operation.

Lock/unlock, soft move preferences, task splitting, and independent defer/drop
semantics were rejected for the first version. Exact placement is easier to
predict, exclusion covers temporary omission, and source task breakdown remains
the path for independently schedulable concrete work.

### Render one keyboard-first decision workbench

The candidate opens in a dedicated read-only `special-mode` buffer consistent
with Portfolio Review. Commands mutate the in-memory candidate while rendering
remains read-only. The buffer contains a compact header followed by three ordered
sections: Schedule, Omissions, and Consequences.

```text
LifeOS Schedule Candidate             CURRENT | FITS
Horizon: Mon Oct 19 11:00 - Sun Oct 25 23:59

Schedule
Mon Oct 19
09:00  [FIXED]       Team planning                    60m
11:00  [KEEP]        Draft architecture note          90m
14:00  [MOVED: USER] Prepare client proposal           60m
                      previously Mon 13:00
16:00  [CAP]         Website redesign capacity       120m

Omissions
[EXCL] Review storage options                          45m
       User excluded; source task unchanged
[OMIT] Prepare migration notes                         60m
       Solver omitted; lower utility than placed work

Consequences
Hard feasibility: passes       Safety: passes
Keep 8 | Move 1 | Add 1 | Remove 0 | Exclude 1
```

The header always shows candidate condition, plain planning status, horizon, and
whether displayed proof is current or prior context. The renderer uses explicit
text labels so meaning never depends on color:

- `[FIXED]` is an immutable calendar or timed source commitment.
- `[KEEP]` is a carried candidate placement unchanged from the current plan.
- `[NEW]` is newly proposed task work.
- `[MOVED: USER]` is an exact user placement and shows its prior interval.
- `[MOVED: PLAN]` is a stability-adjusted carried placement and explains why it
  moved.
- `[CAP]` is coarse project capacity, not a concrete task.
- `[EXCL]` is demand the user explicitly excluded from this candidate.
- `[OMIT]` is demand the solver did not place.

The main buffer shows the candidate, not two complete side-by-side schedules. The
authoritative baseline appears through `[KEEP]` and moved/added/removed deltas;
changed blocks show their previous interval. First-time generation labels all
placed flexible work `[NEW]` or `[CAP]`.

`n` and `p` move between selectable blocks with wrapping, `RET` opens block
details, `v` visits the snapshot-bound source, `m` places the selected candidate
task exactly, `x` excludes candidate demand, `e` applies a candidate-only
estimate, `u` undoes the latest candidate edit, `r` regenerates stale input, `a`
reviews and accepts the complete candidate, `d` discards after confirmation, `R`
restores the previous plan when available, `h` opens contextual help, and `q`
quits the window without accepting. Invalid commands explain the required state
or selection. Interactive commands require confirmation before discarding edits
or writing authoritative plan data.

Portfolio Review adds `s` to open a candidate from its exact displayed snapshot;
its control summary and contextual help advertise that key. A stale review
requires refresh before `s` can create an acceptable candidate.

Block details show candidate interval, source identity, source estimate and
deadline, work mode, placement or omission rationale, relevant margins and
intention effects, candidate overrides, and actions. Coarse-capacity detail must
state that it is a project reservation rather than an invented task. Source
buttons and commands remain bound to markers from the rendered snapshot.

The omissions section separates user exclusions from solver omissions and keeps
their effort and consequences visible. The consequences section shows hard
feasibility, safety, reserve, intention, confidence, capacity, assumptions, and
conflicts, followed by counts and details for kept, moved, added, removed,
excluded, and omitted work compared with the current plan.

Every edit rerenders immediately with a visible checking marker on affected work,
sets the condition to `EDITING` and then `CHECKING`, reports `NEED INFO`, and
disables acceptance until matching evidence becomes current. Rerendering
preserves the logical selection by candidate source and role when possible and
otherwise moves to the nearest surviving selectable block without unexpectedly
changing the window start.

Place prompts for date and aligned start, displays the derived end from the
candidate duration, and requires confirmation before applying the exact
placement. Exclude confirmation explicitly says the source task or project is not
cancelled or edited. Re-estimate shows the source estimate beside the candidate
override and offers source navigation rather than implying that acceptance will
update the source.

Regenerating a stale candidate does not attempt to merge or replay edits. It lists
the candidate edits that will be lost, requires confirmation when any exist, and
then creates a fresh candidate from current authoritative input.

### Review consequences before whole-plan acceptance

Invoking accept opens a review that names the replacement boundary, status and
evidence freshness, plan-level consequences, and counts of kept, moved, added,
removed, excluded, and omitted work. It states that the complete machine-owned
future plan will be replaced and that source tasks, projects, and calendar events
will not be modified.

`FITS` offers normal confirmation. `AT RISK` shows the specific failed policies
and requires an additional explicit risk confirmation. `NEED INFO` and `DOES NOT
FIT` do not offer a confirming write action. Successful acceptance closes the
candidate and reports the number of accepted future blocks, acceptance time, and
whether bounded previous-plan restore is available.

Normal candidate generation chooses a replacement boundary at the first aligned
time not inside an accepted block. If an accepted block is in progress, the
boundary advances to its end and the workbench explains that the block is being
preserved. If authoritative changes create an intersecting block after generation,
acceptance refuses and requires regeneration rather than splitting it.

### Debounce analysis and key responses to the candidate revision

Each mutation schedules one feasibility request after a configurable short idle
delay, replacing any unsent request. A request carries candidate ID, revision,
captured input fingerprint, normalized request ID, exact placements, exclusions,
and estimate overrides. In-flight work need not be cancelled, but a response can
be applied only when those identity fields still match the open candidate and
independent verification succeeds.

While editing or checking, the UI may show the last verified result as previous
evidence, but the current revision's primary status is `NEED INFO` and acceptance
is disabled. Older, malformed, mismatched, or unverifiable responses are
diagnostic context only.

### Use a deterministic plain-status projection

The primary status is computed with this precedence:

1. `NEED INFO` when current-revision evidence is absent, running, stale,
   incomplete, invalid, unknown, or fails independent verification.
2. `DOES NOT FIT` when complete verified evidence proves a hard deadline,
   availability, fixed/current-plan, dependency, or exact-placement conflict.
3. `AT RISK` when hard constraints fit but configured safety, reserve, intention,
   estimate-confidence, or capacity-margin policy is not satisfied.
4. `FITS` when evidence is complete and verified and all hard and configured risk
   checks pass.

The UI retains proof status, margins, assumptions, freshness, omissions, and
conflicts beneath this projection. A `CURRENT` candidate has trustworthy evidence;
its status still determines whether normal acceptance is appropriate. `NEED INFO`
is never acceptable. `AT RISK` requires explicit warning confirmation. `DOES NOT
FIT` cannot replace the current plan.

### Store one machine-owned current plan under planning.org

The current flexible plan lives under an `Accepted schedule` subtree in the
authoritative `planning.org` file. The subtree carries plan-level metadata:

```org
* Accepted schedule
:PROPERTIES:
:LIFEOS_PLAN_ID: generated-plan-id
:LIFEOS_PLAN_SOURCE_FINGERPRINT: normalized-input-fingerprint
:LIFEOS_PLAN_HORIZON_START: 2026-10-19T09:00:00-04:00
:LIFEOS_PLAN_HORIZON_END: 2026-11-16T00:00:00-05:00
:LIFEOS_PLAN_ACCEPTED_AT: 2026-10-16T12:00:00-04:00
:END:
```

Each direct child is one generated block with an active Org timestamp range and
canonical properties:

```org
** Planned block
:PROPERTIES:
:ID: generated-block-id
:LIFEOS_PLAN_KIND: TASK
:LIFEOS_PLAN_TASK_ID: source-task-id
:LIFEOS_PLAN_PROJECT_ID: owning-project-id
:LIFEOS_PLAN_START: 2026-10-19T09:00:00-04:00
:LIFEOS_PLAN_END: 2026-10-19T10:00:00-04:00
:LIFEOS_PLAN_MINUTES: 60
:END:
<2026-10-19 Mon 09:00-10:00>
```

`LIFEOS_PLAN_KIND` is `TASK` or `PROJECT_CAPACITY`. Task blocks require
`LIFEOS_PLAN_TASK_ID`; reservations require `LIFEOS_PLAN_PROJECT_ID`. Start, end,
and minutes are normative; the active timestamp range is the Org-facing
projection and must agree. Titles and block IDs are descriptive generation
artifacts and are not stable across accepted plans.

The subtree is machine-owned. Direct manual editing is unsupported and detected
through its fingerprint before replacement or restore. The records do not use
`SCHEDULED`: a timed `SCHEDULED` value is a fixed commitment, while current-plan
blocks remain replaceable flexible planning input. Invalid or contradictory
records produce `NEED INFO` rather than being silently ignored.

### Replace the complete future plan in one guarded transaction

Solver, portfolio, scenario, rendering, and manipulation code receives no Org
write capability. The acceptance service receives a complete current verified
candidate, never raw Org text or an arbitrary block subset.

Preflight reparses authoritative inputs and requires the normalized source
fingerprint, candidate revision, normalized request ID, current-plan subtree,
horizon, block structure, fixed commitments, and target-buffer state to match.
One plan-level fingerprint is deliberately conservative: any relevant input
change invalidates the whole candidate and requires refresh.

The service preserves accepted records ending at or before the candidate horizon
start and replaces every record beginning at or after it with the complete
candidate. Candidate generation proactively advances the boundary past an
in-progress accepted block. A record that intersects the captured boundary after
generation blocks acceptance; LifeOS does not split or rewrite it.
Records beyond the candidate horizon are also replaced so the accepted future is
one coherent plan rather than a mixture of generations.

The service constructs the complete new `planning.org` content before mutation
and applies one atomic change to its live clean buffer followed by a successful
save. Any validation, edit, or save failure leaves the prior accepted plan
unchanged. Filesystem replacement behind a visited Emacs buffer was rejected
because the buffer could later overwrite or detach from the new file.

### Offer only a bounded single-session restore

Each successful acceptance may retain the exact previous and resulting accepted
subtree text and fingerprints in memory. Restore is offered only for the most
recent acceptance in the current Emacs session and only while the subtree still
matches the resulting fingerprint. It applies the previous subtree through the
same guarded transaction and then regenerates evidence.

If Emacs restarts or any intervening accepted-subtree edit or acceptance occurs,
restore is unavailable. Persistent transaction history and record-level conflict
diagnosis were rejected for the initial version; the user can always generate and
accept another complete candidate.

Candidate-edit undo and previous-plan restore remain separate commands so an
in-memory placement edit cannot appear to reverse an authoritative write.

## Risks / Trade-offs

- [Whole-plan replacement prevents incremental commitment] -> Exclude unwanted
  work and finish reviewing the complete candidate before acceptance.
- [Exact placement can make a candidate infeasible] -> Report the precise
  conflict and let the user undo or choose another interval.
- [Concrete tasks cannot be split] -> Break genuinely independent work into
  source tasks; add solver-level splitting only after observed need.
- [One source change invalidates the complete candidate] -> Prefer conservative
  refresh over fine-grained merge and hash semantics in the initial version.
- [Generated block IDs change across accepted plans] -> Use source task and
  project attribution for navigation and transient consequence comparison.
- [Replacing the whole future can create excessive churn] -> Seed candidates from
  the current plan and use a stability objective to retain unchanged placements
  where the user has not placed or excluded work explicitly. This objective may
  move an untouched seed, but never an exact user placement.
- [A current plan can drift from completed or changed source work] -> Mark the plan
  stale and require regeneration; do not silently infer execution or mutate task
  state.
- [The target buffer may be dirty] -> Refuse acceptance until the user saves or
  resolves the buffer rather than attempting a cross-state merge.
- [Restore disappears after restart or intervening changes] -> Present it as a
  bounded convenience, not durable history.
- [Plain statuses can hide nuance] -> Keep them as a projection and retain proof,
  safety, intention, capacity, assumptions, and freshness drilldowns.

## Migration Plan

1. Add failing tests for candidate conditions, monotonic revisions, status
   projection, debounce coalescing, and response identity checks.
2. Add parsing and validation for the empty or absent machine-owned `Accepted
   schedule` subtree; absence means no current flexible plan.
3. Extend request/result data only as needed for exact placements, exclusions,
   draft estimate overrides, and independent verification.
4. Implement the read-only workbench and run it against shadow results while the
   acceptance service remains disabled.
5. Add whole-plan replacement, dirty-buffer and conflict injection tests, and
   bounded single-session restore using temporary Org files.
6. Enable guarded acceptance and update the manual and integrity checks.
7. Roll back by disabling acceptance and continuing to treat an existing valid
   accepted subtree as occupied flexible context until it is explicitly removed
   or replaced.

## Open Questions

- The configurable risk thresholds and debounce duration should reuse existing
  LifeOS policy where values already exist; any new defaults must be documented
  as policy rather than hidden UI behavior.
- Candidate generation should preserve unchanged current-plan placements when
  feasible, but the exact stability objective can remain an implementation-time
  policy decision as long as explicit user placements remain exact.
