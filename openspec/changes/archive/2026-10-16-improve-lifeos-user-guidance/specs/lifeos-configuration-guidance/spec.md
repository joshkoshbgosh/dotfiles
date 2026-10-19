## ADDED Requirements

### Requirement: Explicit configuration layers
LifeOS SHALL present configuration as distinct layers: fixed schema vocabularies, Emacs implementation preferences, recurring planning policy, complete weekly policy overrides, and per-project overrides. Guidance MUST state the precedence and authoritative storage location of each layer.

#### Scenario: User asks where to change safety policy
- **WHEN** the user opens configuration guidance for safety buffers and reserves
- **THEN** it directs them to recurring or weekly Solver configuration and explains any per-project override

#### Scenario: User asks where to add a work mode
- **WHEN** the user inspects `WORK_MODE` or `DEFAULT_WORK_MODE` guidance
- **THEN** it identifies the allowed values as fixed schema vocabulary rather than a weekly default

### Requirement: Dedicated LifeOS customization group
All LifeOS `defcustom` preferences SHALL belong to a dedicated LifeOS customization group with user-language descriptions that distinguish fallback behavior from authoritative Org policy.

#### Scenario: Open LifeOS Customize group
- **WHEN** the user chooses LifeOS Emacs preferences from the settings entry point
- **THEN** Emacs opens a group containing the LifeOS scaffold, analysis, solver, calendar-assurance, reserve, travel, stress, and command preferences

### Requirement: Single settings entry point
LifeOS SHALL provide one interactive settings entry point using user-language choices for Emacs preferences, recurring planning policy, current-week policy, project overrides at point, and configuration help. The user MUST NOT need to recall variable, property, heading, or table names to reach the selected destination.

#### Scenario: Open recurring policy
- **WHEN** the user chooses recurring planning policy
- **THEN** LifeOS visits the authoritative recurring policy location in `planning.org` or explains that it is missing

#### Scenario: Open current-week policy
- **WHEN** the user chooses this week's policy override
- **THEN** LifeOS visits the matching `#week` policy location or explains that no complete override exists

#### Scenario: Open project overrides outside a project
- **WHEN** the user chooses project-specific overrides and point is not within an explicit project
- **THEN** LifeOS reports the required context without changing any Org file

### Requirement: Confirmed configuration scaffolding
If configuration guidance offers to create a missing policy section or complete table template, it SHALL describe the destination and precedence before prompting, SHALL require explicit confirmation, and SHALL leave source unchanged on cancellation or failed validation.

#### Scenario: Cancel missing-table creation
- **WHEN** a required recurring policy table is absent and the user declines insertion
- **THEN** `planning.org` remains byte-for-byte unchanged

#### Scenario: Insert complete template
- **WHEN** the user confirms creation of a missing solver-configuration template
- **THEN** the inserted table contains every required key exactly once and is accepted by the existing parser

### Requirement: Configuration guidance is contextual
Diagnostics and reports caused by missing or invalid configuration SHALL link or direct the user to the appropriate settings destination and relevant manual section.

#### Scenario: Incomplete weekly solver configuration
- **WHEN** assurance is unknown because a selected weekly Solver configuration is incomplete
- **THEN** the finding identifies the weekly override as the source and offers the corresponding configuration path
