## ADDED Requirements

### Requirement: Manual teaches the candidate-review-replace workflow
The LifeOS manual SHALL provide an action-first workflow for opening a schedule
candidate, identifying fixed, authoritative current-plan, carried candidate, new
candidate, coarse-capacity, and excluded work, applying exact placement,
exclusion, draft-only re-estimation, and edit undo, reading live consequences,
accepting the complete plan, discarding the candidate, and restoring the
immediately previous plan when available.

#### Scenario: User follows the primary workflow
- **WHEN** a user opens the adjustable-schedule workflow chapter
- **THEN** it first gives the command and ordered review-adjust-check-accept actions, expected visible outcomes, and recovery for stale or non-fitting candidates

#### Scenario: User learns the workbench labels
- **WHEN** a user reads the primary workflow
- **THEN** it defines fixed, kept, new, user-moved, planner-moved, coarse-capacity, excluded, and solver-omitted labels and explains that changed blocks show their prior intervals

#### Scenario: User compares undo and restore
- **WHEN** a user needs to reverse an action
- **THEN** the manual distinguishes transient candidate-edit undo from bounded single-session restoration of the latest accepted plan

### Requirement: Manual distinguishes candidates and the current plan
The manual SHALL state that solver placements and candidate edits are transient
and read-only until explicit complete acceptance. It SHALL document the
machine-owned `Accepted schedule` representation in `planning.org`, explain that
the current flexible plan differs from timed fixed `SCHEDULED` commitments, and
state that acceptance replaces the complete future plan without changing source
task or project metadata.

#### Scenario: User adjusts candidate work
- **WHEN** a user places, excludes, or re-estimates candidate work
- **THEN** the manual states which transient candidate edit changed and that the source task, project, and current accepted plan did not

#### Scenario: User inspects the current plan
- **WHEN** a user follows current-plan reference guidance
- **THEN** they can identify plan provenance, replacement horizon, block kind, source attribution, and exact interval and can distinguish the generated records from `SCHEDULED`

#### Scenario: User wants to edit one accepted block
- **WHEN** a user wants to change part of the current plan
- **THEN** the manual directs them to generate and accept a complete replacement candidate rather than manually editing machine-owned records

### Requirement: Manual documents status and freshness protection
The manual SHALL define `FITS`, `AT RISK`, `DOES NOT FIT`, and `NEED INFO`, their
precedence, and the retained detailed proof dimensions. It SHALL separately define
`EDITING`, `CHECKING`, `CURRENT`, and `STALE`, and explain debounce, revision
checking, plan-level source validation, whole-plan replacement, dirty-buffer and
in-progress-boundary refusal, transactional failure, and bounded restore.

#### Scenario: User sees NEED INFO while recomputing
- **WHEN** a changed candidate is waiting for or running feasibility analysis
- **THEN** the manual explains that any previous result is context only and current acceptance remains disabled

#### Scenario: Replacement fails preflight
- **WHEN** authoritative input or the current plan changed before commit
- **THEN** recovery guidance explains that nothing was written and directs the user to refresh and review a new current candidate

#### Scenario: Stale candidate contains edits
- **WHEN** regeneration would discard candidate edits
- **THEN** the manual explains that the first version lists and discards confirmed edits rather than automatically merging them with changed authoritative input

#### Scenario: Candidate is at risk or does not fit
- **WHEN** a current candidate reports `AT RISK` or `DOES NOT FIT`
- **THEN** the manual explains that at-risk replacement requires explicit warning confirmation while a non-fitting candidate cannot be accepted
