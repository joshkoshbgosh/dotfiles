## Context

LifeOS currently exposes planning evidence through reports, but it does not have
a single operational surface for choosing the next action or recovering the rest
of a disrupted day. The new surface must combine authoritative Org state,
calendar commitments, weekly intentions, optional solver evidence, clock state,
and incomplete inbox items without turning a momentary adjustment into a change
to recurring policy.

The separate adjustable-schedule-drafts change may eventually provide accepted
and proposed plan blocks plus a guarded acceptance transaction. Today and
recovery must be useful before that change exists, while adopting its accepted
blocks and acceptance boundary when available. Solver results are asynchronous
and can be stale or unavailable, and incomplete task metadata must not leave the
user without a useful next step.

## Goals / Non-Goals

**Goals:**

- Provide one Today dashboard as the normal entry point for choosing work,
  checking today's plan, and recovering after disruption.
- Produce one explained recommendation and a bounded set of alternatives that
  fit the remaining day and current work mode as far as current evidence proves.
- Apply remaining-time, work-mode, and protected-outcome check-in answers only
  to the current day, without rewriting weekly policy or task metadata.
- Replan only the future portion of the day, preserving fixed and explicitly
  protected commitments and requiring consequence review before acceptance.
- Work with either a date-scoped in-memory Today plan or accepted schedule-draft
  blocks through a narrow integration adapter.
- Degrade from current solver evidence to local deterministic selection and
  actionable repair without overstating feasibility.

**Non-Goals:**

- Replacing Portfolio Review, weekly planning, project grooming, or detailed
  solver diagnostics.
- Automatically changing deadlines, estimates, project commitments, recurring
  availability, weekly intentions, or historical clock records.
- Guaranteeing that heuristic recommendations are globally feasible.
- Implementing the adjustable schedule-draft workbench or its Org persistence
  format as part of this change.
- Automatically accepting a recovered plan or silently dropping a commitment.

## Decisions

### Use one snapshot-backed Today dashboard

Today will be one read-only rendered dashboard backed by an immutable snapshot.
The snapshot contains the local date and current minute, source identities,
fixed commitments, accepted flexible blocks when available, active clock state,
candidate tasks, intention progress, inbox findings, daily overrides, and the
freshness and provenance of planning evidence. Commands act on captured source
identities and refresh after mutations such as clocking or completion.

This keeps all daily decisions in one surface and prevents sections from mixing
different solver requests or retargeting a source after Org changes. Separate
buffers for recommendations, intention progress, and recovery were rejected
because they recreate the navigation and interpretation burden this change is
intended to remove.

### Rank recommendations through an evidence-aware pipeline

Recommendation selection uses one ordered candidate pipeline:

1. Continue an active clock or honor an accepted block that is current and still
   actionable.
2. Use a fitting placement from current solver evidence.
3. Use a deterministic local ranking over actionable tasks based on hard timing,
   readiness, current work mode, remaining usable time, protected outcome, and
   weekly intention deficits.
4. If no work item can be recommended safely, offer a bounded useful fallback,
   such as processing a specific incomplete inbox item, reviewing the nearest
   fixed commitment, or capturing the missing information that blocks selection.

Alternatives come from the same candidate set and disclose why they fit or what
is unproved. Evidence labels distinguish accepted-plan, solver-backed, and local
recommendations. The local path was chosen over making the dashboard wait for a
solver because recovery must remain useful during solver failure and while task
metadata is incomplete. An arbitrary first-task fallback was rejected because it
could hide readiness, duration, or fixed-commitment conflicts.

### Keep daily check-in state date-scoped and non-authoritative

The check-in produces a date-keyed daily override object containing remaining
usable windows or minutes, current work mode, and at most one protected outcome.
It overlays recurring and weekly inputs for Today recommendation and recovery
only. It is cleared at local-day rollover or explicit reset and never writes
weekly policy, task properties, calendar data, or project metadata.

The initial implementation may retain this object only in Emacs runtime state;
loss on restart is acceptable because the answers are lightweight and explicitly
ephemeral. Persisting it in Org was rejected because that would blur observation
of today's circumstances with durable planning policy.

### Model recovery as a preview-and-accept transaction from the current minute

Recovery captures what changed using a small set of facts: completed or skipped
work, an overrun, reduced remaining capacity, changed work mode, or urgent new
work. Existing authoritative completion and clock data remain authoritative;
the disruption answers are scenario inputs rather than retroactive edits.

Replanning freezes elapsed time and starts the planning horizon at the captured
current minute. Fixed commitments are always constraints. The user can protect
accepted flexible blocks or one outcome; protection means the planner must keep
the commitment or report that the protected set is infeasible, never silently
relax it. Unprotected future proposed placements are obsolete and excluded from
the rebuilt remainder.

Every result is a preview with a categorized consequence set: stayed, moved,
deferred, and no longer fits. Acceptance is disabled until the review is shown.
This transaction boundary was chosen over immediate regeneration because users
must understand losses and trade-offs before the plan changes.

### Isolate optional schedule-draft integration behind a plan adapter

The Today core consumes a plan adapter with operations to read today's accepted
and proposed blocks, build a replan scenario, and accept a reviewed result. When
adjustable schedule drafts are present, the adapter uses accepted blocks as plan
context, discards unprotected proposed future blocks during recovery, and
delegates acceptance to the draft capability's guarded write transaction.

Without that capability, a built-in adapter derives context from Org, calendar,
clock, and available analysis, and acceptance installs a date-scoped in-memory
Today plan. It does not synthesize accepted Org timestamps. This keeps the first
release useful while avoiding a second persistent schedule representation that
would later require migration.

### Separate recommendation confidence from plan feasibility

The dashboard exposes evidence as current, stale, local-only, running, or
unavailable and presents plan feasibility independently from whether a next
action is useful. Stale solver output may be shown as context but cannot be the
sole proof that an action fits. Missing metadata identifies the unproved claim
and offers source/groom actions, but metadata repair replaces the recommendation
only when no bounded actionable choice can be made safely.

This reuses the evidence semantics of Portfolio Review and avoids both false
precision and an all-or-nothing failure mode.

## Risks / Trade-offs

- [Local fallback recommends work that later proves globally infeasible] -> Label
  it local-only, check known fixed commitments and duration bounds, and avoid
  claiming global feasibility.
- [Protected items cannot all fit] -> Preserve them as constraints, report the
  conflict, and require the user to change protection or capacity explicitly.
- [Optional draft integration creates divergent behavior] -> Keep both paths
  behind the same snapshot, consequence, and acceptance contracts and run shared
  conformance tests against both adapters.
- [Date-scoped state is lost on Emacs restart] -> Keep check-in short, show when
  no override is active, and do not imply that ephemeral input is durable policy.
- [Asynchronous results race with dashboard actions] -> Tie evidence and source
  actions to request and source snapshot identities; reject superseded results.
- [A dense dashboard increases cognitive load] -> Keep recommendation and direct
  actions first, alternatives bounded, and proof details and repair guidance
  progressively disclosed.

## Migration Plan

1. Add snapshot, daily override, recommendation, and built-in plan-adapter data
   structures without changing existing planning commands.
2. Ship the Today dashboard and local fallback path with schedule-draft support
   absent by default.
3. Add recovery preview and date-scoped in-memory acceptance, guarded by tests
   that no Org or recurring policy is changed implicitly.
4. Register the optional schedule-draft adapter when its capability is available
   and run the same Today and recovery contract tests against it.
5. Update the manual and daily entry points after dashboard behavior is enabled.

Rollback removes the dashboard entry points and adapter registration. Because
daily overrides and the pre-draft accepted plan are ephemeral, rollback requires
no data migration; accepted Org blocks created by a future draft adapter remain
owned by that capability.

## Open Questions

- Which compact key bindings should Today advertise while remaining consistent
  with existing LifeOS review buffers?
- Should date-scoped check-in state later survive an Emacs restart in a cache
  that is still explicitly non-authoritative?
