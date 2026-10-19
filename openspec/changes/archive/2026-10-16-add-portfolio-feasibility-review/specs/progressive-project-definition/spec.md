## ADDED Requirements

### Requirement: Project inventory uses only explicit project identity
The system SHALL inventory every explicitly tagged `#project` and every
executable task without a recognized project. It SHALL NOT infer projects from
deadlines, hierarchy, or descendant work. Orphan tasks SHALL be review findings,
not silently moved into projects.

#### Scenario: Untagged aggregate is ignored as a project
- **WHEN** a non-task heading outside a `#project` has active TODO descendants
- **THEN** the portfolio inventory does not classify or list it as a project

#### Scenario: Orphan task is called out
- **WHEN** an executable `#task` has no nearest `#project` ancestor
- **THEN** the portfolio inventory lists it under orphan work

### Requirement: Explicit projects are scaffolded and guided
The system SHALL scaffold project identity and named storage fields after the user
adds `#project`, and SHALL provide an interactive command that prompts in plain
language for all required project metadata.

#### Scenario: User explicitly marks a project
- **WHEN** the user adds `#project` to a heading or invokes project scaffolding
- **THEN** the system creates an ID and missing project fields without overwriting existing values

#### Scenario: User grooms project metadata
- **WHEN** the user invokes project grooming at a heading
- **THEN** the system prompts for deadline, total effort, work mode, chunk size, and confidence without requiring property-name recall

### Requirement: Active projects have a readiness contract
The system SHALL require every active `#project` to have a stable `ID`, a
parseable `DEADLINE`, and valid effort accounting before it is eligible for a
positive feasibility result. A project with no TODO state, or with `TODO`,
`NEXT`, or `WAITING` state, SHALL be active. Projects in `SOMEDAY`, `DONE`, or
`CANCELLED` SHALL remain visible but SHALL not be committed portfolio demand.

#### Scenario: Deadline is missing
- **WHEN** an active `#project` has no valid deadline
- **THEN** its definition status is `INCOMPLETE` and its feasibility is `UNKNOWN`

#### Scenario: Someday project is visible but uncommitted
- **WHEN** a `#project` has TODO state `SOMEDAY`
- **THEN** the review lists it as uncommitted and excludes its flexible work from portfolio feasibility

### Requirement: Projects support progressive effort definition
The system SHALL accept `PROJECT_EFFORT` as the project's expected total effort,
including executable descendant tasks and work not yet broken down. The value
MUST be a positive 15-minute-aligned `H:MM` duration. A project using coarse work
SHALL also provide a valid `DEFAULT_WORK_MODE`, `PLANNING_CHUNK`, and
`ESTIMATE_CONFIDENCE` of `Low`, `Medium`, or `High`.

#### Scenario: Valid coarse project
- **WHEN** an active project has valid required identity, deadline, total effort, default mode, chunk size, and confidence
- **THEN** the project is eligible for coarse capacity analysis without a complete task breakdown

#### Scenario: Invalid coarse metadata
- **WHEN** coarse project effort, work mode, chunk size, or confidence is missing or malformed
- **THEN** the project is `INCOMPLETE` and each invalid field is reported with a source link

### Requirement: Explicit tasks consume the project effort envelope
The system SHALL calculate unallocated project effort as `PROJECT_EFFORT` minus
the total `EFFORT` of all executable descendant tasks, including completed
tasks. Active task remaining effort SHALL continue to use task `EFFORT` minus
direct task clocks. Explicit task effort SHALL never be added on top of the full
project estimate.

#### Scenario: Partial breakdown reduces coarse work
- **WHEN** a 120-hour project contains executable tasks totaling 25 hours
- **THEN** the project reports 95 hours of unallocated work and 25 hours of explicitly allocated work

#### Scenario: Completed task remains allocated
- **WHEN** an executable descendant task is completed
- **THEN** its declared effort continues to consume the project effort envelope and does not reappear as unallocated work

#### Scenario: Explicit work exceeds project estimate
- **WHEN** executable descendant task effort exceeds `PROJECT_EFFORT`
- **THEN** the project is `INCOMPLETE`, all explicit task demand is retained, and the stale project estimate is reported for review

### Requirement: Coarse work is virtual and deterministic
The system SHALL divide positive unallocated effort into deterministic virtual
chunks no larger than `PLANNING_CHUNK`, with a final smaller chunk when needed.
Each chunk SHALL inherit the project ID, deadline, default work mode, mandatory
status, estimate confidence, and project source evidence. Virtual chunks SHALL
exist only in normalized solver input and reports and SHALL never be written to
Org.

#### Scenario: Virtual chunks represent the residual
- **WHEN** a project has 5 hours of unallocated work and a 2-hour planning chunk
- **THEN** normalization produces deterministic virtual chunks of 2 hours, 2 hours, and 1 hour

#### Scenario: Repeated normalization is stable
- **WHEN** unchanged project input is normalized more than once
- **THEN** the same virtual chunk IDs, durations, evidence, and ordering are produced

### Requirement: Definition status reflects planning detail honestly
The system SHALL classify an active project as `INCOMPLETE` when required data or
effort accounting is invalid, `COARSE` when positive virtual work remains, and
`DETAILED` when no virtual work remains and all active descendant work is valid
and executable. Definition status SHALL be independent from feasibility status.

#### Scenario: Capacity model is valid but not detailed
- **WHEN** a project has valid metadata and positive unallocated effort
- **THEN** its definition status is `COARSE` rather than `INCOMPLETE` or `DETAILED`

#### Scenario: Fully allocated valid project
- **WHEN** project effort is fully allocated to valid executable tasks and no unresolved active descendant work remains
- **THEN** its definition status is `DETAILED`

### Requirement: Coarse proof claims are limited
The system SHALL label a successful solve containing virtual project work as
`CAPACITY FEASIBLE`. It SHALL reserve `STRUCTURALLY FEASIBLE` for a project whose
remaining work is detailed and whose task graph is valid. Estimate confidence
and virtual effort SHALL be shown beside every coarse result.

#### Scenario: Coarse project fits
- **WHEN** all explicit and virtual project work can be placed before the deadline
- **THEN** the project reports `CAPACITY FEASIBLE` and does not claim structural feasibility

#### Scenario: Detailed project fits
- **WHEN** a detailed project's valid task graph can be placed before the deadline
- **THEN** the project reports `STRUCTURALLY FEASIBLE`
