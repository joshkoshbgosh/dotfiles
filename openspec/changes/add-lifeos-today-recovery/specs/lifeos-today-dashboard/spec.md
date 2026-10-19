## ADDED Requirements

### Requirement: Today is the single daily decision surface
LifeOS SHALL provide one Today dashboard that presents, in priority order, one
recommended action, a bounded set of alternatives, today's fixed commitments and
accepted work, weekly intention progress, plan feasibility, and incomplete inbox
items. The dashboard SHALL provide direct actions to refresh, start or clock the
recommendation, visit its source, explain it, change today's capacity, enter
recovery, and open contextual help.

#### Scenario: User opens Today
- **WHEN** the user invokes the Today command
- **THEN** one dashboard presents the current recommendation and daily context without requiring navigation through separate planning reports

#### Scenario: User acts on the recommendation
- **WHEN** the user starts or clocks the displayed recommendation
- **THEN** LifeOS uses the captured source identity, performs the requested Org clock action, and refreshes Today from current state

### Requirement: Recommendations include fitting alternatives and explanations
Today SHALL select one recommendation and no more than five alternatives from
currently actionable work. Selection SHALL account for known fixed commitments,
remaining usable time, readiness, current work mode, the protected outcome, and
weekly intention progress. Each choice SHALL identify its evidence provenance
and explain why it fits; an unproved fit MUST be labeled rather than presented as
solver-proved.

#### Scenario: Current solver placement fits
- **WHEN** current solver evidence places an actionable task within the remaining usable day and known constraints
- **THEN** Today may recommend that task and labels the recommendation as solver-backed with a concise reason

#### Scenario: User wants a different fitting action
- **WHEN** the recommended task is unsuitable but other candidates fit the known current constraints
- **THEN** Today presents a bounded ordered set of alternatives with duration, work-mode, and evidence explanations

#### Scenario: A clock is already active
- **WHEN** Today opens while an actionable task is being clocked
- **THEN** continuing the active task is considered before starting a different task and any contrary recommendation explains why switching is warranted

### Requirement: Daily check-in overrides are ephemeral
LifeOS SHALL let the user provide remaining usable time, current work mode, and at
most one protected outcome for the current local day. These answers SHALL overlay
Today and recovery calculations only, SHALL NOT rewrite recurring or weekly
policy or task and project metadata, and SHALL expire at local-day rollover or an
explicit reset.

#### Scenario: Capacity drops for the rest of today
- **WHEN** the user records less remaining usable time in the daily check-in
- **THEN** Today refreshes recommendations and feasibility using the override while leaving recurring availability unchanged

#### Scenario: Work mode changes
- **WHEN** the user changes today's work mode
- **THEN** subsequent recommendations prefer compatible work and the weekly policy remains unchanged

#### Scenario: Day rolls over
- **WHEN** the local date changes after a daily override was recorded
- **THEN** LifeOS excludes the prior day's override from the new Today snapshot

### Requirement: Today integrates with plans before and after schedule drafts
Today SHALL consume accepted schedule blocks when adjustable schedule drafts are
available. When they are unavailable, Today SHALL derive fixed commitments,
accepted current work, and recommendations from current Org, calendar, clock,
daily override, and available planning evidence without requiring a schedule
draft or inventing accepted Org timestamps.

#### Scenario: Accepted draft exists
- **WHEN** adjustable schedule drafts provide accepted blocks for today
- **THEN** Today displays those blocks as accepted work and considers the current accepted block before unrelated flexible work

#### Scenario: Schedule drafts are not installed
- **WHEN** no schedule-draft provider is available
- **THEN** Today remains fully openable and actionable using its built-in plan adapter

#### Scenario: Only proposed draft blocks exist
- **WHEN** a schedule draft has proposed but unaccepted blocks
- **THEN** Today distinguishes them from accepted work and does not represent them as commitments

### Requirement: Missing evidence does not make Today useless
Today SHALL classify planning evidence as current, stale, local-only, running, or
unavailable. If solver evidence or nonessential metadata is unavailable, Today
SHALL use a deterministic local selection that respects known fixed commitments
and SHALL label unproved feasibility. If no work item can be selected safely, it
SHALL offer a specific useful fallback and the smallest relevant repair action.

#### Scenario: Solver is unavailable but actionable work is known
- **WHEN** the solver is unavailable and a ready task has a known duration that fits before the next fixed commitment
- **THEN** Today recommends from deterministic local evidence, labels it local-only, and does not claim global feasibility

#### Scenario: Metadata is incomplete but does not block selection
- **WHEN** some planning metadata is incomplete but a bounded actionable task can still be selected safely
- **THEN** Today keeps useful work primary and presents metadata repair as a secondary action

#### Scenario: No task can be selected safely
- **WHEN** missing duration, readiness, or source evidence prevents a bounded work recommendation
- **THEN** Today offers a specific inbox-processing, commitment-review, capture, or metadata-repair action instead of displaying an empty recommendation

### Requirement: Today snapshots and actions are freshness-safe
Every rendered Today dashboard SHALL associate recommendations, plan context,
source actions, and feasibility with one snapshot identity. Newer input SHALL
mark the display stale, and an asynchronous response for an older request MUST
NOT replace newer accepted evidence or silently retarget an action.

#### Scenario: Org changes while Today is open
- **WHEN** authoritative Org input changes after the displayed snapshot was built
- **THEN** Today marks affected evidence stale until refreshed and retains source links tied to the displayed snapshot

#### Scenario: Older solver response arrives late
- **WHEN** a superseded solver request returns after a newer Today snapshot exists
- **THEN** LifeOS rejects it as current evidence and does not replace the newer recommendation
