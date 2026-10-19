## ADDED Requirements

### Requirement: Project dependencies are explicit typed relations
The system SHALL recognize `project-depends-on` links in an explicit project's
direct body as project-to-project prerequisites. It SHALL provide an interactive
editor that targets explicit project IDs and SHALL NOT infer whole-project edges
from hierarchy or cross-project task links.

#### Scenario: User adds a project prerequisite
- **WHEN** the user selects another valid explicit project through the project dependency command
- **THEN** the dependent project receives a source-navigable `project-depends-on` relation

#### Scenario: Cross-project task edge remains precise
- **WHEN** one task depends on a task owned by another project without a project relation
- **THEN** only the task prerequisite closure is imposed and no whole-project edge is inferred

### Requirement: Project graph structure is validated before proof
The system SHALL reject or diagnose missing targets, non-project targets,
self-links, duplicate links, project dependency cycles, and cycles formed jointly
with cross-project task prerequisites. Structural errors SHALL prevent a positive
proof and SHALL include source-linked remediation evidence.

#### Scenario: Project dependency cycle exists
- **WHEN** the explicit project graph contains a transitive cycle
- **THEN** every affected committed project is incomplete or unknown and no normal infeasibility is presented as a scheduling result

#### Scenario: Link targets a task ID
- **WHEN** a `project-depends-on` relation resolves to a `#task` rather than a `#project`
- **THEN** project validation reports a wrong-type target error

### Requirement: Project dependencies impose whole-project finish-to-start order
For a project dependency from dependent A to prerequisite B, the system SHALL
require all selected remaining work owned by B to finish before any selected
remaining work owned by A starts. The constraint SHALL include explicit and
virtual work while leaving virtual chunks mutually unordered.

#### Scenario: Detailed prerequisite delays dependent project
- **WHEN** both projects are detailed and contain remaining work
- **THEN** every prerequisite-project placement ends before the first dependent-project placement starts

#### Scenario: Coarse prerequisite delays dependent project
- **WHEN** the prerequisite project contains virtual residual work
- **THEN** all prerequisite virtual chunks finish before dependent-project work begins and the proof remains capacity-level

### Requirement: Proof scopes include transitive prerequisite-project demand
A committed dependent project SHALL pull the complete transitive prerequisite
project closure into isolated and portfolio proof, including task prerequisite
closure and fixed commitments. The result SHALL identify borrowed prerequisite
projects and SHALL not omit required work merely because a prerequisite project
is otherwise uncommitted.

#### Scenario: Uncommitted prerequisite is required by commitment
- **WHEN** a committed project depends on a definition-ready `SOMEDAY` project
- **THEN** the prerequisite project's remaining demand is included and its forced inclusion is disclosed

#### Scenario: Incomplete prerequisite blocks assurance
- **WHEN** a committed project depends on an incomplete project
- **THEN** the dependent project's isolated proof is `UNKNOWN` with the prerequisite's missing evidence

### Requirement: Terminal prerequisite states have explicit semantics
A `DONE` prerequisite with reconciled zero remaining demand SHALL satisfy the
project edge. A `CANCELLED` prerequisite SHALL NOT satisfy a committed dependent.
Stale positive demand on a terminal prerequisite SHALL be diagnosed rather than
silently discarded.

#### Scenario: Completed prerequisite is satisfied
- **WHEN** a prerequisite project is `DONE` and has reconciled zero remaining demand
- **THEN** dependent work is not delayed by historical completed work

#### Scenario: Cancelled prerequisite remains required
- **WHEN** a committed project depends on a `CANCELLED` project
- **THEN** the dependent definition reports an actionable contradiction and cannot receive a positive proof

### Requirement: Forecasting never schedules through unresolved project gates
The visible heuristic SHALL honor finish-to-start project dependencies for
detailed explicit work. When prerequisite completion includes virtual residual
that the heuristic does not place, it SHALL report dependent work unresolved or
unplaced instead of forecasting it before the unknown completion.

#### Scenario: Detailed prerequisite is forecast first
- **WHEN** a detailed prerequisite and dependent both have schedulable explicit work
- **THEN** the heuristic places all remaining prerequisite work before dependent work

#### Scenario: Coarse prerequisite is not fabricated
- **WHEN** a prerequisite project contains virtual residual absent from the heuristic
- **THEN** dependent explicit work is withheld with a disclosed coarse-prerequisite reason

### Requirement: Project dependency results are independently verified
The independent verifier SHALL check prerequisite-project completion against
dependent-project start, required predecessor inclusion, and project ownership.
Violation SHALL invalidate the returned proof with both projects attributed.

#### Scenario: Forged result overlaps dependent projects
- **WHEN** a returned dependent placement starts before prerequisite-project work finishes
- **THEN** independent verification rejects the result and assurance becomes `UNKNOWN`

### Requirement: Portfolio UI supports dependency remediation
Portfolio rows and drilldowns SHALL show direct prerequisites, dependents,
transitive borrowed projects, dependency cycles, and related conflict evidence
with snapshot-safe source links. Analysis and report rendering SHALL remain
read-only.

#### Scenario: User inspects an unknown dependent project
- **WHEN** a project is unknown because its prerequisite is incomplete
- **THEN** the drilldown links to both the dependency source and the incomplete prerequisite project
