## ADDED Requirements

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
