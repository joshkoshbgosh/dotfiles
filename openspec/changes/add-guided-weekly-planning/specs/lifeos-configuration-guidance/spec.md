## MODIFIED Requirements

### Requirement: Explicit configuration layers
LifeOS SHALL present configuration as distinct layers: fixed schema vocabularies, Emacs implementation preferences, recurring planning policy, weekly availability exception overlays, complete weekly intention and Solver configuration replacements, and per-project overrides. Guidance MUST state the precedence, merge or replacement behavior, and authoritative storage location of each layer.

#### Scenario: User asks where to change safety policy
- **WHEN** the user opens configuration guidance for safety buffers and reserves
- **THEN** it directs them to recurring or complete weekly Solver configuration and explains any per-project override

#### Scenario: User asks where to add a work mode
- **WHEN** the user inspects `WORK_MODE` or `DEFAULT_WORK_MODE` guidance
- **THEN** it identifies the allowed values as fixed schema vocabulary rather than a weekly default

#### Scenario: User changes one day's availability
- **WHEN** the user wants to remove or add availability for one date
- **THEN** guidance directs them to a weekly availability exception and states that unrelated recurring windows remain effective

### Requirement: Single settings entry point
LifeOS SHALL provide one interactive settings entry point using user-language choices for Emacs preferences, recurring planning policy, guided weekly planning, advanced raw weekly policy, project overrides at point, and configuration help. The user MUST NOT need to recall variable, property, heading, or table names to reach the selected destination.

#### Scenario: Open recurring policy
- **WHEN** the user chooses recurring planning policy
- **THEN** LifeOS visits the authoritative recurring policy location in `planning.org` or explains that it is missing

#### Scenario: Plan the current week
- **WHEN** the user chooses guided weekly planning
- **THEN** LifeOS opens an in-memory draft for the selected week rather than creating or modifying weekly Org policy

#### Scenario: Open raw current-week policy
- **WHEN** the user chooses advanced raw weekly policy
- **THEN** LifeOS visits the matching `#week` policy location or explains that it is missing without representing the whole week as one universal replacement layer

#### Scenario: Open project overrides outside a project
- **WHEN** the user chooses project-specific overrides and point is not within an explicit project
- **THEN** LifeOS reports the required context without changing any Org file

### Requirement: Confirmed configuration scaffolding
If configuration guidance offers to create a missing policy section, canonical exception table, or complete replacement table, it SHALL describe the destination and applicable precedence before prompting, SHALL preview the exact source change, SHALL require explicit confirmation, and SHALL leave source unchanged on cancellation, stale source, failed validation, or failed serialization.

#### Scenario: Cancel missing-table creation
- **WHEN** required policy storage is absent and the user declines insertion
- **THEN** `planning.org` remains byte-for-byte unchanged

#### Scenario: Insert complete solver template
- **WHEN** the user confirms creation of a missing Solver configuration template
- **THEN** the inserted table contains every required key exactly once and is accepted by the existing parser

#### Scenario: Insert availability exceptions
- **WHEN** the user confirms valid guided additions and removals for a week with no weekly heading
- **THEN** LifeOS creates the canonical week location and exception table without copying the complete recurring availability table

## ADDED Requirements

### Requirement: Configuration preview exposes effective values
Configuration guidance SHALL provide a preview that distinguishes recurring source, existing weekly source, draft changes, and effective values. It MUST identify overlay behavior separately from complete replacement behavior and MUST show the canonical Org destination before a write.

#### Scenario: Preview mixed weekly policy
- **WHEN** a week has availability exceptions, weekly intentions, and inherited recurring Solver configuration
- **THEN** the preview labels availability as overlaid, intentions as weekly replacement, and Solver configuration as recurring
