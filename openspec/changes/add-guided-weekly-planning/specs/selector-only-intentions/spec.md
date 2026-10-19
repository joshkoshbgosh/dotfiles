## MODIFIED Requirements

### Requirement: Intentions are the only weekly allocation input
The system SHALL use the selected five-column `Intentions` table for both solver optimization and heuristic allocation reporting. A matching weekly table SHALL replace recurring intentions as a whole, including when it was produced by guided weekly planning. The guided planner MUST display and write the complete effective weekly set after any intention edit. The system SHALL NOT parse Domain budget tables or generate compatibility intentions when no Intentions table exists.

#### Scenario: No intentions are configured
- **WHEN** neither weekly nor recurring Intentions exist
- **THEN** work remains schedulable and the system reports that no allocation targets are configured

#### Scenario: Weekly intentions exist
- **WHEN** a matching week has a valid Intentions table
- **THEN** those rows replace recurring rows for solver and heuristic accounting

#### Scenario: Guided edit changes one recurring row
- **WHEN** the user changes one inherited intention in guided weekly planning
- **THEN** the resulting weekly table contains the complete reviewed intention set rather than a one-row overlay

### Requirement: Explicit and virtual work share selector accounting
The system SHALL include matching explicit task IDs and virtual coarse-work IDs in intention matches. Project selectors for virtual work SHALL use the owning project evidence. Overlapping intentions SHALL independently credit matching explicit work, virtual work, direct clocked time, and eligible timed calendar events without double-counting physical capacity. Reports and guided previews MUST disclose shared matches and MUST NOT sum intention rows as total demand or progress.

#### Scenario: Coarse project matches an intention
- **WHEN** virtual work belongs to a project selected by project ID, tag, or property
- **THEN** every matching virtual chunk contributes to that intention's planned allocation

#### Scenario: One task matches multiple intentions
- **WHEN** a task matches two intention selectors
- **THEN** its minutes contribute independently to both rows while its placement consumes availability once

## ADDED Requirements

### Requirement: Intention bounds are ordered soft preferences
Each intention minimum, target, and maximum SHALL be optional and SHALL accept a non-negative `H:MM` duration, with `0:00` representing an explicit zero and an empty cell representing no bound. Supplied bounds MUST be ordered so every present minimum is no greater than every present target or maximum and every present target is no greater than every present maximum. Minimum shortfall and maximum excess SHALL be optimized before target deviation and SHALL remain soft allocation findings rather than hard schedule constraints.

#### Scenario: Only a minimum is supplied
- **WHEN** an intention has minimum `3:00` and blank target and maximum cells
- **THEN** allocation below three hours reports shortfall and allocation at or above three hours has no target deviation or maximum excess

#### Scenario: Explicit zero maximum is supplied
- **WHEN** an intention has maximum `0:00`
- **THEN** matching allocation is reported as maximum excess rather than treating the cell as omitted

#### Scenario: Soft bound conflicts with mandatory work
- **WHEN** satisfying mandatory work causes maximum excess
- **THEN** the hard schedule can remain feasible and the excess is reported separately

### Requirement: Guided selector construction preserves the restricted language
LifeOS SHALL provide a typed builder for every supported selector primitive and for nested `and`, `or`, and `not` forms. The builder SHALL use canonical inventories and vocabularies where available, SHALL show canonical selector text and plain-language meaning, and SHALL preview matches across explicit tasks, virtual project work, and timed calendar sources. Raw selector editing SHALL remain available through canonical Org policy and SHALL use the same restricted parser and evaluator.

#### Scenario: Select one explicit project
- **WHEN** the user chooses a project from the selector builder
- **THEN** the builder stores its stable project ID in a `project-id` selector and previews that project's explicit and virtual work

#### Scenario: Compose nested exclusions
- **WHEN** the user builds all tasks with a tag except one work mode
- **THEN** the builder emits a valid nested `and` and `not` selector accepted by the canonical parser

### Requirement: Calendar credit is bounded and source-aware
Only clipped minutes from timed imported events with a matching canonical `CALENDAR_ROLE` SHALL credit an intention. All-day events, generated travel, and remote setup SHALL contribute zero allocation credit even when they block availability. Guided and raw selectors MUST use identical calendar-role evaluation.

#### Scenario: Timed event crosses the weekly boundary
- **WHEN** a matching timed event begins before the selected week and ends inside it
- **THEN** only the event minutes inside the week credit the intention

#### Scenario: Generated travel shares a role
- **WHEN** generated travel carries evidence associated with a matching calendar event
- **THEN** the travel reduces capacity but contributes zero intention credit
