## ADDED Requirements

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
