# portfolio-review-interaction Specification

## Purpose
TBD - created by archiving change improve-lifeos-user-guidance. Update Purpose after archive.
## Requirements
### Requirement: Self-describing Portfolio Review
The Portfolio Review buffer SHALL identify what it shows, state that analysis is read-only, summarize how project rows and drilldowns relate, and display a compact list of available controls without exposing the Lisp mode name as a required user concept.

#### Scenario: Open Portfolio Review
- **WHEN** the user opens Portfolio Review
- **THEN** the first screen explains its purpose, read-only boundary, evidence state, and primary controls before the detailed rows

### Requirement: Explicit evidence freshness
Portfolio Review SHALL classify its displayed evidence as `RUNNING`, `CURRENT`, `STALE`, `LOCAL ONLY`, or `UNAVAILABLE`. A stale or local-only display MUST NOT visually imply a current solver proof.

#### Scenario: No accepted solver result
- **WHEN** local project inventory exists but no accepted solver result exists
- **THEN** the review displays `LOCAL ONLY` and labels proof fields unavailable rather than current

#### Scenario: Newer analysis invalidates accepted evidence
- **WHEN** Org edits invalidate analysis after a result was accepted
- **THEN** the open review displays `STALE` until matching evidence is accepted

#### Scenario: Solver request is active
- **WHEN** a newer solver request is running
- **THEN** the review displays `RUNNING` while preserving and clearly labeling any older result

### Requirement: Keyboard-operable review workflow
Portfolio Review SHALL provide and advertise commands to refresh evidence, move to the next or previous project, visit the selected source, groom the selected project, open contextual help, and quit. Commands requiring a selected project SHALL fail with an actionable message when no project is selected.

#### Scenario: Refresh from the report
- **WHEN** the user invokes refresh in Portfolio Review
- **THEN** LifeOS rebuilds project analysis, requests solver evidence when enabled, and updates the evidence-state display

#### Scenario: Groom a selected project
- **WHEN** point identifies a project row or drilldown and the user invokes project grooming
- **THEN** LifeOS visits that captured project source and starts the existing explicit grooming flow

#### Scenario: Activate source
- **WHEN** point is on a source button and the user activates it
- **THEN** Emacs visits the marker captured by the reviewed snapshot

### Requirement: Stable asynchronous rendering
Asynchronous Portfolio Review updates SHALL preserve useful window and point context where possible, and source buttons MUST remain tied to the snapshot whose evidence is displayed.

#### Scenario: Result arrives while review is open
- **WHEN** a solver result arrives while the user is reading a project drilldown
- **THEN** the buffer updates without unnecessarily returning visible windows to the beginning

#### Scenario: Source changed after snapshot
- **WHEN** authoritative Org changes after the reviewed snapshot
- **THEN** the report marks evidence stale and does not silently retarget old evidence to a different heading

### Requirement: User-facing terminology
Portfolio Review headings, controls, and help SHALL use user concepts such as project, evidence, refresh, source, and grooming. Internal mode names, request plumbing, and protocol object names MAY appear only in developer diagnostics or deep reference.

#### Scenario: Request help
- **WHEN** the user opens help from Portfolio Review
- **THEN** the help describes actions and outcomes without requiring knowledge of `my/lifeos-portfolio-review-mode`

### Requirement: Portfolio Review presents a plain planning status
Portfolio Review SHALL project current detailed evidence to `FITS`, `AT RISK`,
`DOES NOT FIT`, or `NEED INFO` using the schedule-draft status mapping, while
retaining freshness, definition, isolated proof, portfolio proof, safety,
intention, capacity, margin, assumption, and conflict detail.

#### Scenario: Detailed evidence is incomplete
- **WHEN** any required current portfolio evidence is absent, stale, unknown, invalid, running, or unverified
- **THEN** the compact planning status is `NEED INFO` and no lower-level green field overrides it

#### Scenario: Portfolio fits with risk
- **WHEN** current verified evidence satisfies hard constraints but violates configured risk policy
- **THEN** the compact planning status is `AT RISK` and the affected proof dimensions remain visible

### Requirement: Portfolio Review opens the schedule-candidate workflow
Portfolio Review SHALL provide and advertise a keyboard-operable action that opens
one schedule candidate derived from the exact displayed snapshot. Opening it
SHALL remain read-only; the review and help SHALL explain that only a separate
explicit, current, verified whole-plan acceptance transaction can replace the
machine-owned future plan.

#### Scenario: Open draft from current evidence
- **WHEN** the user invokes the draft action from a current review
- **THEN** the workbench opens a candidate tied to the review's normalized request ID and input fingerprint

#### Scenario: Open draft from stale evidence
- **WHEN** the user invokes the draft action while the review is stale
- **THEN** the system refreshes or requires refresh and does not present the stale placements as an acceptable current candidate

#### Scenario: User reads write-boundary help
- **WHEN** the user opens contextual help for schedule candidates
- **THEN** it distinguishes read-only generation and manipulation from explicit whole-plan replacement and bounded restore

#### Scenario: User sees the candidate entry action
- **WHEN** Portfolio Review renders current evidence
- **THEN** its control summary and contextual help advertise `s` as the key that opens the schedule candidate
