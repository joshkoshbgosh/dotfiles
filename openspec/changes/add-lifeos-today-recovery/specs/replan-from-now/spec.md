## ADDED Requirements

### Requirement: Recovery captures disruption without rewriting history
LifeOS SHALL provide a guided Replan from now workflow that can capture completed
or skipped work, an overrun, reduced capacity, a changed work mode, and urgent new
work. Captured disruption facts SHALL be scenario inputs; the workflow MUST NOT
rewrite completed work, clock history, recurring policy, deadlines, estimates, or
project commitments unless the user invokes an existing explicit editing action.

#### Scenario: Meeting overrun reduces the day
- **WHEN** the user records an overrun and less remaining usable time
- **THEN** recovery builds a scenario from current authoritative history and the reduced future capacity without altering the historical meeting or recurring policy

#### Scenario: Urgent work arrives
- **WHEN** the user identifies a newly captured urgent task during recovery
- **THEN** the task enters the recovery scenario if actionable and its authoritative source remains unchanged until an explicit source edit

### Requirement: Replanning begins at the current minute
Replan from now SHALL freeze elapsed time, use the captured current minute as the
new planning-horizon start, retain completed and elapsed blocks as history, and
rebuild only the remaining portion of the local day. Unprotected proposed future
placements SHALL be discarded as obsolete before regeneration.

#### Scenario: A planned block was missed
- **WHEN** its time has passed and the user invokes Replan from now
- **THEN** recovery records the block as elapsed or missed context and does not place new work before the captured current minute

#### Scenario: Future proposal is obsolete
- **WHEN** an unaccepted proposed block begins after the recovery time
- **THEN** the old proposal is excluded from the rebuilt remainder and is not treated as an accepted commitment

### Requirement: Fixed and protected commitments are preserved
Fixed commitments SHALL always constrain recovery. Before regeneration, LifeOS
SHALL let the user explicitly protect eligible accepted flexible commitments and
one protected outcome. The planner SHALL retain protected items or return a
visible protected-set conflict; it MUST NOT silently move, defer, drop, or relax
them.

#### Scenario: Calendar event overlaps flexible work
- **WHEN** recovery encounters a fixed calendar commitment and an unprotected flexible block at the same time
- **THEN** the fixed commitment remains and the flexible work is moved, deferred, or reported as no longer fitting

#### Scenario: Protected commitments conflict
- **WHEN** the selected protected commitments cannot all fit within remaining known capacity
- **THEN** recovery reports the protected-set conflict and requires the user to change protection or capacity before a plan can be accepted

#### Scenario: Protected outcome has multiple candidate tasks
- **WHEN** the protected outcome can be advanced by more than one actionable task
- **THEN** recovery preserves sufficient fitting work for the outcome without implying that every associated task is individually fixed

### Requirement: Recovery requires consequence review and explicit acceptance
Every recovery result SHALL be a preview that categorizes affected work as stayed,
moved, deferred, or no longer fits and explains material deadline, capacity,
intention, and protection consequences. LifeOS SHALL show this consequence review
before enabling explicit acceptance and SHALL leave the current plan unchanged if
the user cancels.

#### Scenario: Rebuilt day changes placements
- **WHEN** recovery produces a candidate remainder with moved and deferred work
- **THEN** the review lists what stayed, moved, was deferred, and no longer fits before offering acceptance

#### Scenario: User cancels review
- **WHEN** the user exits consequence review without accepting
- **THEN** neither the existing accepted plan nor authoritative Org planning data changes

#### Scenario: Work no longer fits
- **WHEN** reduced capacity prevents all remaining work from fitting
- **THEN** the review names the affected work, distinguishes proof from heuristic assessment, and requires explicit acceptance of the consequence

### Requirement: Recovery degrades usefully without solver proof
If current solver evidence cannot be obtained, recovery SHALL still build a
deterministic local preview from known fixed commitments, accepted work,
actionable tasks, durations, daily overrides, and protections. The preview SHALL
label feasibility as local-only or unavailable and MUST NOT silently drop a fixed
or protected item. If insufficient metadata prevents regeneration, recovery SHALL
retain known commitments and offer a specific bounded next action.

#### Scenario: Solver fails during recovery
- **WHEN** the solver fails but known durations and fixed commitments permit a local ordering
- **THEN** recovery presents a local-only consequence preview that can be reviewed and accepted without claiming solver proof

#### Scenario: Metadata prevents safe regeneration
- **WHEN** unknown duration or readiness makes the remaining flexible plan unsafe to construct
- **THEN** recovery preserves known commitments and offers a specific repair, inbox-processing, or manual next-action fallback

### Requirement: Recovery supports both plan adapters
When adjustable schedule drafts are available, recovery SHALL consume accepted
blocks, discard unprotected future proposals, and delegate accepted changes to
the draft capability's guarded acceptance transaction. Without schedule drafts,
recovery SHALL use a date-scoped in-memory Today plan and MUST NOT write synthetic
accepted schedule timestamps to Org.

#### Scenario: Recover an accepted schedule draft
- **WHEN** accepted draft blocks exist and the user accepts the reviewed recovery
- **THEN** LifeOS applies the revision through the schedule-draft acceptance boundary with its freshness and conflict checks

#### Scenario: Recover before schedule drafts exist
- **WHEN** no schedule-draft provider exists and the user accepts the reviewed recovery
- **THEN** LifeOS installs the candidate as today's ephemeral plan and refreshes Today without modifying Org scheduling fields

#### Scenario: Source changes before acceptance
- **WHEN** authoritative source or plan input changes after preview generation
- **THEN** acceptance is blocked until recovery is refreshed and reviewed against current input
