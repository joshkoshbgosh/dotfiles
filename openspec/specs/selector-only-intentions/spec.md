# selector-only-intentions Specification

## Purpose
TBD - created by archiving change add-portfolio-feasibility-review. Update Purpose after archive.
## Requirements
### Requirement: Task validity has no fixed classification property
The system SHALL NOT require, scaffold, groom, inherit, validate, serialize, or
report a `DOMAIN` property. Tasks and projects SHALL remain valid when they match
no intention selector.

#### Scenario: Unclassified task is valid
- **WHEN** an executable task has valid execution metadata but no classification tag or property
- **THEN** it remains eligible for graph analysis, forecasting, and solving

### Requirement: Intentions are the only weekly allocation input
The system SHALL use the selected five-column `Intentions` table for both solver
optimization and heuristic allocation reporting. A matching weekly table SHALL
replace recurring intentions as a whole. The system SHALL NOT parse Domain budget
tables or generate compatibility intentions when no Intentions table exists.

#### Scenario: No intentions are configured
- **WHEN** neither weekly nor recurring Intentions exist
- **THEN** work remains schedulable and the system reports that no allocation targets are configured

#### Scenario: Weekly intentions exist
- **WHEN** a matching week has a valid Intentions table
- **THEN** those rows replace recurring rows for solver and heuristic accounting

### Requirement: Selector evaluation is source-aware and composable
The system SHALL support `tag`, `project-tag`, `project-id`, `prop`,
`project-prop`, `work-mode`, `calendar-role`, `source task`, and nested `and`,
`or`, and `not`. Task primitives SHALL inspect task/project evidence,
`calendar-role` SHALL inspect calendar events, and boolean forms SHALL evaluate
recursively over each source type. The former `domain` selector SHALL be rejected.

#### Scenario: Compound task and calendar intention
- **WHEN** an intention uses `(or (project-tag "school") (calendar-role "school"))`
- **THEN** matching project work and timed school calendar events both contribute to the row

#### Scenario: Domain selector is used
- **WHEN** a selector contains `(domain "School")`
- **THEN** parsing fails with an unsupported-selector diagnostic

### Requirement: Explicit and virtual work share selector accounting
The system SHALL include matching explicit task IDs and virtual coarse-work IDs in
intention matches. Project selectors for virtual work SHALL use the owning project
evidence. Overlapping intentions SHALL independently credit matching work without
double-counting physical capacity.

#### Scenario: Coarse project matches an intention
- **WHEN** virtual work belongs to a project selected by project ID, tag, or property
- **THEN** every matching virtual chunk contributes to that intention's planned allocation

### Requirement: Calendar roles replace calendar domains
The calendar importer SHALL map configured calendars to canonical
`CALENDAR_ROLE` values and SHALL never write or normalize `DOMAIN`. Timed matching
events SHALL credit intentions; all-day events, generated travel, and remote setup
SHALL not credit allocation even when they block capacity.

#### Scenario: Role-mapped timed event
- **WHEN** a timed imported event has a role matched by an intention
- **THEN** its clipped event duration contributes to actual allocation

#### Scenario: All-day role-mapped event
- **WHEN** an all-day event matches a calendar role
- **THEN** it may block availability but contributes zero intention minutes

### Requirement: Reports use intention selectors rather than domains
Placement, remaining-work, weekly pressure, and ledger reports SHALL identify
matching intention names and selector evidence. Rows MAY overlap and SHALL state
that totals are independent views. Domain-named report columns, dynamic blocks,
and compatibility assumptions SHALL not remain.

#### Scenario: Work matches multiple intentions
- **WHEN** one task matches two intention selectors
- **THEN** both rows report the task's minutes and the placement lists both intention names

### Requirement: Legacy Domain interfaces are removed
The implementation and active documentation SHALL contain no LifeOS `DOMAIN`
schema, Domain budget parser, domain selector, Domain compatibility fallback, or
separate fixed-category time-budget module. Legacy Org data requires an explicit
one-time migration and SHALL not be silently supported.

#### Scenario: Legacy Domain budget table remains
- **WHEN** planning data contains only a Domain budget table
- **THEN** it supplies no allocation policy and the review directs the user to create selector-based Intentions

