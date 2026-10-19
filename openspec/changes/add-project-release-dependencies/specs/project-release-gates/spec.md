## ADDED Requirements

### Requirement: Projects may declare an optional not-before bound
The system SHALL recognize an optional project `NOT_BEFORE` Org timestamp as a
hard lower bound on all remaining work owned by that explicit project. It SHALL
accept date-only and timed timestamps, treat an absent or scaffold-empty value as immediately
releasable, treat a past value as valid but nonbinding, and classify a malformed
value as an incomplete project definition.

#### Scenario: Future date gates project work
- **WHEN** a committed project has a valid future date-only `NOT_BEFORE`
- **THEN** no selected work owned by that project starts before local midnight on that date

#### Scenario: Malformed optional bound is not ignored
- **WHEN** an explicit project contains a malformed `NOT_BEFORE`
- **THEN** its definition is `INCOMPLETE` and its feasibility is `UNKNOWN`

### Requirement: Project and task release bounds compose
The system SHALL preserve task-local release evidence separately from the owning
project bound and enforce the maximum applicable lower bound. Project release
SHALL apply to explicit work, virtual work, and fixed work, while borrowed work
owned by another project SHALL use its own project's bounds.

#### Scenario: Task has a later local release
- **WHEN** a task's valid release is later than its project's not-before bound
- **THEN** the task cannot start before its later task-local release

#### Scenario: Fixed work contradicts project release
- **WHEN** project-owned work has a fixed start before the project not-before bound
- **THEN** the proof reports an attributed conflict rather than exempting the fixed work

#### Scenario: Coarse virtual work inherits project release
- **WHEN** a coarse project has positive virtual residual and a future not-before bound
- **THEN** every generated virtual chunk is constrained by that project bound

### Requirement: Effective bounds remain scenario-correct
The normalized model SHALL preserve task-local deadlines and releases independently
from project-level bounds, and SHALL derive effective upper and lower bounds after
project scenarios are applied. Project not-before scenarios SHALL distinguish an
absent change, an explicit clear, and a replacement value.

#### Scenario: Project deadline changes beside task deadline
- **WHEN** a scenario changes a project deadline for a task that also has its own deadline
- **THEN** the effective deadline is recomputed as the earlier current bound rather than retaining the baseline result

#### Scenario: Scenario clears project release
- **WHEN** a scenario explicitly clears a project's not-before bound
- **THEN** task-local releases remain enforced and the baseline project bound is removed

### Requirement: Latest safe project start searches the project bound
The latest-safe-project-start negotiation SHALL search the latest aligned project
not-before bound that preserves the requested assurance across all remaining
explicit, virtual, and fixed owned work. It SHALL return `UNKNOWN` when the target
project is incomplete, uncommitted, or absent from modeled demand.

#### Scenario: Fixed work limits latest project start
- **WHEN** a later candidate project bound would fall after fixed owned work
- **THEN** that candidate is infeasible during the boundary search

#### Scenario: Incomplete project is queried
- **WHEN** latest safe project start is requested for an incomplete project
- **THEN** the query returns `UNKNOWN` without an optimistic boundary

### Requirement: Forecast and portfolio expose project release gates
The visible forecast SHALL honor project not-before bounds for explicit work. The
portfolio review and project drilldown SHALL display the source bound, effective
constraint findings, and source navigation. Guided project grooming SHALL prompt
for immediate versus delayed availability without requiring property-name recall.

#### Scenario: User grooms a delayed project
- **WHEN** the user chooses that project work cannot begin immediately
- **THEN** guided grooming records a validated not-before timestamp

#### Scenario: Forecast sees a future project gate
- **WHEN** otherwise-ready explicit work belongs to a future-gated project
- **THEN** the heuristic places it no earlier than the project bound or reports it unplaced

### Requirement: Release constraints are independently verified
The independent verifier SHALL reject any returned placement that starts before
its task-local or owning-project release bound and SHALL identify the affected
task and project.

#### Scenario: Forged virtual placement violates project release
- **WHEN** a returned virtual placement starts before its owning project's not-before bound
- **THEN** independent verification rejects the result and assurance becomes `UNKNOWN`
