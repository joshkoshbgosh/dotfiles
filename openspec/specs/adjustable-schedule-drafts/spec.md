# adjustable-schedule-drafts Specification

## Purpose
TBD - created by syncing change add-adjustable-schedule-drafts. Update Purpose after implementation.
## Requirements
### Requirement: LifeOS maintains one transient schedule candidate
The system SHALL expose at most one active schedule candidate with a stable
candidate ID, captured normalized-input fingerprint, monotonic revision,
replacement horizon, complete candidate placements, exclusions, draft estimate
overrides, edit history, and matching feasibility evidence. Its live condition
SHALL be exactly one of `EDITING`, `CHECKING`, `CURRENT`, or `STALE`. Only a
`CURRENT` candidate with verified matching evidence SHALL be eligible to replace
the current plan.

#### Scenario: Initial candidate becomes current
- **WHEN** generation returns independently verified evidence matching the candidate ID, input fingerprint, and current revision
- **THEN** the workbench enters `CURRENT` and presents one complete candidate future plan

#### Scenario: Source changes beneath a candidate
- **WHEN** authoritative task, project, calendar, availability, intention, policy, or current-plan input changes
- **THEN** the candidate enters `STALE`, retains its prior display as stale context, and cannot replace the current plan

#### Scenario: User regenerates a stale edited candidate
- **WHEN** the user requests regeneration and candidate edits would be lost
- **THEN** the workbench lists the affected edits, requires confirmation, and creates a fresh candidate without silently rebasing or replaying them

#### Scenario: User discards a candidate
- **WHEN** the user confirms discard
- **THEN** the workbench closes, releases transient edits, and writes no Org data

### Requirement: Candidate generation distinguishes block roles
The workbench SHALL visibly distinguish fixed commitments, the authoritative
current-plan baseline, carried and newly proposed candidate task blocks, proposed
coarse project-capacity reservations, and explicitly excluded demand. Replaceable
future current-plan blocks SHALL seed source-attributed candidate placements
rather than also acting as hard occupied intervals in the replacement solve. The
workbench SHALL expose source identity and placement or omission rationale
without presenting a coarse reservation as a concrete task sequence.

#### Scenario: Mixed schedule is displayed
- **WHEN** a candidate contains fixed, current-plan baseline, carried candidate, new candidate, capacity, and excluded work
- **THEN** each role has distinct labels and explanations, the authoritative baseline remains read-only, and carried or new candidate work is directly manipulable

#### Scenario: Coarse project demand is placed
- **WHEN** a project has virtual residual effort but no concrete task structure for that effort
- **THEN** the candidate shows attributable project-capacity reservations and does not invent task names or ordering

### Requirement: The workbench is keyboard-operable and decision-oriented
The system SHALL render the candidate in a dedicated read-only workbench with a
header and ordered Schedule, Omissions, and Consequences sections. The header
SHALL always show candidate condition, plain planning status, replacement horizon,
and evidence freshness. The Schedule SHALL group blocks chronologically by day
and label fixed, kept, new, user-moved, planner-moved, and coarse-capacity work in
text. The Omissions section SHALL distinguish explicit user exclusions from
solver omissions. The Consequences section SHALL retain detailed proof and show
kept, moved, added, removed, excluded, and omitted deltas from the current plan.

#### Scenario: User reviews a revised plan
- **WHEN** a candidate is seeded from an existing current plan
- **THEN** the main schedule shows one candidate with change labels and prior intervals for changed blocks rather than rendering two complete schedules side by side

#### Scenario: User navigates candidate work
- **WHEN** the user invokes next or previous block commands
- **THEN** point moves between selectable blocks with wrapping and source and action commands operate on snapshot-bound block metadata

#### Scenario: User opens block details
- **WHEN** the user requests details for a task block
- **THEN** the workbench shows its interval, source, estimate, deadline, work mode, rationale, relevant margins and intention effects, overrides, and available actions

#### Scenario: User opens coarse-capacity details
- **WHEN** the user requests details for a project-capacity reservation
- **THEN** the workbench identifies its project, residual effort, and confidence and states that the reservation is not a concrete task

#### Scenario: Workbench rerenders after analysis
- **WHEN** an asynchronous update changes rendered content
- **THEN** the workbench preserves the logical selection and window context when possible and otherwise selects the nearest surviving block

#### Scenario: User reads controls
- **WHEN** the workbench or contextual help is rendered
- **THEN** it advertises next, previous, details, source, exact place, exclude, candidate estimate, undo, regenerate, complete accept, discard, restore, help, and quit commands with actionable invalid-state messages

### Requirement: Users can adjust the candidate without source writes
The system SHALL support exact placement, exclusion, draft-only re-estimation,
and latest-edit undo as reversible candidate edits. No edit SHALL change source
task or project metadata, calendar data, current-plan records, or timed
`SCHEDULED` values.

#### Scenario: Place a candidate block exactly
- **WHEN** the user places a carried or new candidate task block at an aligned start
- **THEN** the next analysis either uses that exact interval or reports why it conflicts and does not silently move it

#### Scenario: Exact placement is awaiting proof
- **WHEN** the user confirms a valid date and aligned start for a candidate block
- **THEN** the block moves immediately with a checking indication, the candidate becomes ineligible for acceptance, and its status remains `NEED INFO` until matching evidence arrives

#### Scenario: Exclude proposed demand
- **WHEN** the user excludes selected task demand or a coarse reservation
- **THEN** omitted effort and its deadline, safety, intention, and capacity consequences remain explicit and the source item is not cancelled or modified

#### Scenario: Exclusion requires informed confirmation
- **WHEN** the user invokes exclusion
- **THEN** confirmation states that the source item remains unchanged before moving it to the explicit-exclusions view

#### Scenario: Re-estimate proposed demand
- **WHEN** the user supplies a candidate-only effort estimate
- **THEN** analysis uses the override and acceptance does not write the estimate to Org

#### Scenario: Re-estimate distinguishes source and candidate values
- **WHEN** the user invokes candidate re-estimation
- **THEN** the prompt displays the source estimate and candidate override separately and offers source navigation for an authoritative estimate change

#### Scenario: Undo a candidate edit
- **WHEN** the user undoes the latest placement, exclusion, or estimate override
- **THEN** the inverse edit creates a new revision without writing Org

### Requirement: Feasibility updates are live, debounced, and revision-safe
Every candidate edit SHALL render immediately, increment the revision, invalidate
acceptance eligibility, and schedule a background feasibility request after a
configurable idle debounce. A response SHALL become current evidence only when
its candidate ID, revision, captured input fingerprint, normalized request ID,
and independent verification result match the open candidate.

#### Scenario: Several edits occur rapidly
- **WHEN** multiple candidate operations occur inside the debounce interval
- **THEN** the UI reflects every edit immediately and only the latest unsent revision is requested after the idle interval

#### Scenario: Older response arrives last
- **WHEN** a response for an earlier revision arrives after a newer revision exists
- **THEN** the system rejects it as current evidence and does not change the newer candidate or its acceptance eligibility

#### Scenario: Current response fails verification
- **WHEN** a matching response contradicts independent placement or consequence verification
- **THEN** the candidate remains ineligible for acceptance, reports `NEED INFO`, and exposes the verification failure

### Requirement: Consequences use a bounded plain status
The workbench SHALL summarize the current revision as `NEED INFO`, `DOES NOT FIT`,
`AT RISK`, or `FITS`, in that precedence. `NEED INFO` SHALL cover absent, running,
stale, incomplete, invalid, unknown, or unverified current evidence. `DOES NOT
FIT` SHALL cover a proven hard conflict. `AT RISK` SHALL cover hard-feasible work
that fails configured safety, reserve, intention, estimate-confidence, or capacity
margin policy. `FITS` SHALL require complete verified evidence satisfying hard and
configured risk checks. Detailed proof SHALL remain available.

#### Scenario: Previous fit is being recomputed
- **WHEN** an edited revision is checking and the previous revision was `FITS`
- **THEN** the current primary status is `NEED INFO` and the previous fit is labeled only as prior evidence

#### Scenario: Deadline is impossible
- **WHEN** verified complete evidence proves a hard deadline conflict
- **THEN** the primary status is `DOES NOT FIT`, acceptance is disabled, and conflicting sources and margins remain available

#### Scenario: Hard plan fits without safety margin
- **WHEN** all hard constraints fit but configured safety cannot be met
- **THEN** the primary status is `AT RISK`, hard feasibility and safety failure are shown separately, and acceptance requires explicit warning confirmation

#### Scenario: All checks pass
- **WHEN** complete current evidence passes hard, safety, reserve, intention, estimate-confidence, and capacity-margin checks
- **THEN** the primary status is `FITS`

### Requirement: The current plan has a canonical machine-owned Org representation
The system SHALL store the current flexible plan only beneath the machine-owned
`Accepted schedule` subtree in authoritative `planning.org`. The subtree SHALL
identify one plan ID, normalized source fingerprint, replacement horizon, and
acceptance time. Each generated direct child SHALL identify block kind, exact
interval, and duration with an agreeing active Org timestamp range. Task blocks
SHALL identify their source task and project; project-capacity blocks SHALL
identify their source project. Generated block IDs and titles SHALL NOT be relied
on as stable identity across accepted plans, and records MUST NOT use or modify
`SCHEDULED`.

#### Scenario: Current plan contains task and capacity blocks
- **WHEN** a complete candidate containing both kinds is accepted
- **THEN** both are serialized beneath one plan-level identity and each retains source attribution without claiming that a capacity block is a concrete task

#### Scenario: Stored projection disagrees
- **WHEN** a record's active timestamp range disagrees with its normative start, end, or minutes properties
- **THEN** the system reports `NEED INFO` and does not silently use either representation

#### Scenario: Direct manual edit is detected
- **WHEN** machine-owned accepted-subtree content differs from the captured fingerprint
- **THEN** replacement or restore is refused until the plan is refreshed or the conflict is explicitly resolved

### Requirement: Acceptance replaces the complete future plan transactionally
The system SHALL expose acceptance only for the complete current candidate. Before
writing, it MUST reparse authoritative input and validate the candidate revision,
normalized request ID, plan-level source fingerprint, current-plan subtree,
block structure, replacement horizon, fixed commitments, and target-buffer state.
It SHALL preserve accepted records ending at or before the horizon start and
replace every accepted record beginning at or after it with the complete
candidate through one atomic edit and successful save of `planning.org`, or leave
the prior plan unchanged. It MUST NOT write source tasks, projects, calendars,
estimates, deadlines, states, or timed `SCHEDULED` values.

#### Scenario: Complete replacement succeeds
- **WHEN** the user explicitly accepts a current verified `FITS` candidate and preflight still matches authoritative input
- **THEN** the complete candidate becomes the current future plan in one transaction and no source task or project is modified

#### Scenario: Acceptance review precedes confirmation
- **WHEN** the user invokes acceptance for an eligible candidate
- **THEN** the system first shows replacement boundary, evidence freshness, status, material consequences, and kept, moved, added, removed, excluded, and omitted counts and states exactly which authoritative content will and will not change

#### Scenario: At-risk replacement is confirmed
- **WHEN** the user explicitly confirms a current verified `AT RISK` candidate after reviewing the warning
- **THEN** the complete candidate may replace the current future plan while its risk evidence remains available

#### Scenario: Candidate does not fit
- **WHEN** current verified evidence reports `DOES NOT FIT`
- **THEN** acceptance remains disabled and the existing current plan is unchanged

#### Scenario: Input changed after verification
- **WHEN** any relevant authoritative input or the current-plan subtree differs at acceptance time
- **THEN** acceptance is refused even if the displayed candidate previously reported `FITS`

#### Scenario: Accepted block intersects the replacement boundary
- **WHEN** authoritative input changes after generation so an accepted block begins before and ends after the captured candidate horizon start
- **THEN** acceptance is refused rather than splitting or rewriting the in-progress block

#### Scenario: Candidate opens during an accepted block
- **WHEN** the requested horizon start falls inside a valid accepted block
- **THEN** generation advances the replacement boundary to the block's aligned end, preserves that block, and explains the adjusted boundary

### Requirement: The most recent plan replacement has bounded restore
The system SHALL retain at most one in-memory restore token for the most recent acceptance
in the current Emacs session. The token SHALL contain exact prior and resulting
accepted-subtree text and fingerprints. Restore SHALL be offered only while the
current subtree still matches the resulting fingerprint and SHALL apply the prior
subtree through the same guarded transaction before regenerating evidence.

#### Scenario: Restore an unchanged latest acceptance
- **WHEN** the current session retains a restore token and the accepted subtree still matches its resulting fingerprint
- **THEN** the exact prior subtree is restored atomically and current evidence is regenerated

#### Scenario: Acceptance reports completion
- **WHEN** complete replacement succeeds
- **THEN** the candidate closes and the system reports accepted future block count, acceptance time, and whether previous-plan restore is available

#### Scenario: Restore is no longer safe
- **WHEN** Emacs restarted, another acceptance occurred, or the accepted subtree changed
- **THEN** bounded restore is unavailable and no authoritative content is overwritten
