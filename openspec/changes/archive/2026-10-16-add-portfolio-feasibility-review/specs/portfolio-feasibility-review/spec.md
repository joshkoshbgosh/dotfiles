## ADDED Requirements

### Requirement: Portfolio review is the top-level planning surface
The system SHALL provide a read-only portfolio review with one row per recognized
project and a separate section for orphan work. Project rows
SHALL show commitment, definition status, deadline, total effort, explicit and
virtual remaining effort, isolated feasibility, portfolio status, minimum margin,
estimate confidence, and the next actionable finding.

#### Scenario: User opens the review
- **WHEN** the portfolio review command is invoked
- **THEN** it displays current explicit project rows followed by orphan work without modifying Org

#### Scenario: User drills into a finding
- **WHEN** the user activates a project, task, or diagnostic source in the review
- **THEN** the system visits the captured Org source associated with the reviewed snapshot

### Requirement: Project feasibility is proved in isolation
For each definition-ready active project, the system SHALL test that project's
explicit tasks, virtual work, and transitive prerequisites against global
availability, calendar, sleep, reserve, travel, and fixed commitments. Flexible
work from unrelated projects SHALL be excluded from the isolated proof. A
cross-project prerequisite SHALL remain included and visibly attributed.

#### Scenario: Project fits without competing flexible work
- **WHEN** one ready project's complete scoped demand fits around global fixed constraints
- **THEN** its isolated feasibility is `FEASIBLE` with hard and safety margins

#### Scenario: External prerequisite is required
- **WHEN** a project task depends on a task owned by another project
- **THEN** the prerequisite is included in the isolated proof and both project relationships are disclosed

#### Scenario: Project input is incomplete
- **WHEN** a project is not definition-ready
- **THEN** no positive isolated proof is claimed and its isolated feasibility is `UNKNOWN`

### Requirement: Portfolio feasibility covers every committed project
The system SHALL test all definition-ready active projects together with global
constraints. If any active project is incomplete, the portfolio definition SHALL
be `INCOMPLETE` and the system SHALL not present the portfolio as green even when
the modeled subset is feasible. Uncommitted projects SHALL be excluded and
disclosed.

#### Scenario: All committed projects fit
- **WHEN** every active project is definition-ready and all committed demand fits together
- **THEN** portfolio feasibility is `FEASIBLE` and each project row reports its status in that global witness

#### Scenario: Modeled subset fits but a project is incomplete
- **WHEN** ready project demand fits but another active project lacks required data
- **THEN** modeled-subset feasibility is disclosed and overall portfolio credibility remains `INCOMPLETE`

#### Scenario: Projects fit alone but conflict together
- **WHEN** two projects are independently feasible but their combined demand is infeasible
- **THEN** the portfolio is `INFEASIBLE` and affected projects are shown as conflict-involved without claiming a unique culprit

### Requirement: Status dimensions remain separate
The review SHALL keep definition, isolated proof, and portfolio result in separate
fields. It SHALL use `INCOMPLETE`, `COARSE`, or `DETAILED` for definition;
`FEASIBLE`, `INFEASIBLE`, `UNKNOWN`, or `UNCOMMITTED` for isolated proof; and
`FITS`, `TIGHT`, `CONFLICT-INVOLVED`, `UNKNOWN`, or `UNCOMMITTED` for portfolio
status. It SHALL not collapse these dimensions into one unexplained color.

#### Scenario: Coarse project fits in a failing portfolio
- **WHEN** a coarse project is isolated-feasible but participates in a globally infeasible core
- **THEN** the row independently shows `COARSE`, `FEASIBLE`, and `CONFLICT-INVOLVED`

### Requirement: Project margins and conflicts are attributable
Feasible project results SHALL report minimum hard-deadline and safety margins
over project-owned explicit and virtual work. Infeasible results SHALL return
structured task IDs and project IDs for each conflict when derivable. Shared and
global constraints SHALL be labeled as shared rather than assigned to an
arbitrary project.

#### Scenario: Project has a narrow margin
- **WHEN** the smallest project-owned deadline margin is positive but a configured safety buffer cannot be met
- **THEN** the project is portfolio `TIGHT` and the hard and safety margins are shown separately

#### Scenario: Conflict spans projects
- **WHEN** an infeasible core contains constraints from multiple projects
- **THEN** every derivable involved project is listed and the report states that core membership is not unique causal attribution

### Requirement: Portfolio results are snapshot-safe
Project summaries, source links, isolated results, and portfolio results SHALL be
associated with the same normalized request ID. Newer input SHALL mark displayed
results stale and SHALL prevent responses from older requests from replacing
newer accepted evidence.

#### Scenario: Org changes during project solving
- **WHEN** project or portfolio input changes before an asynchronous response returns
- **THEN** the stale response is rejected and the last internally consistent result remains visibly stale

### Requirement: Project scenarios are composable and read-only
The system SHALL let the user compose in-memory changes to a project's total
effort, deadline, commitment status, and coarse metadata alongside existing busy,
task-estimate, intention, and fixed-commitment changes. A scenario SHALL recompute
both project and portfolio evidence and SHALL never persist changes to Org or the
calendar.

#### Scenario: Test a later project deadline
- **WHEN** the user changes a project's deadline in a scenario and runs it
- **THEN** inherited task and virtual-work deadlines are recomputed and baseline-versus-scenario project deltas are reported

#### Scenario: Test deferring a project
- **WHEN** the user marks an active project uncommitted in a scenario
- **THEN** its flexible demand is excluded from scenario portfolio feasibility while the baseline and Org remain unchanged

### Requirement: Negotiation answers project planning questions
The system SHALL provide project-scoped queries for maximum feasible project
effort, minimum required project work in a window, latest safe project start,
earliest feasible project deadline, and a minimal set of candidate projects to
defer for portfolio feasibility. Queries SHALL state whether they use deadline-only
or safety assurance and whether they apply to baseline or scenario input.

#### Scenario: Find maximum project scope
- **WHEN** the user asks for maximum safe effort for a project under the current portfolio
- **THEN** the result reports the largest aligned project effort that preserves configured safety

#### Scenario: Find a feasible deadline
- **WHEN** the user asks for the earliest feasible deadline for a project
- **THEN** the result returns an aligned date-time bound or explains why no bound is provable within the horizon

#### Scenario: Find projects to defer
- **WHEN** an infeasible portfolio is queried with a candidate set of projects
- **THEN** the result returns a deterministic minimal defer set or reports `UNKNOWN` without modifying commitments

### Requirement: Existing rollout safety remains intact
The portfolio review, project proofs, scenarios, and negotiation results SHALL be
shadow evidence. They SHALL not replace heuristic overlays, write timestamps,
change project metadata, or schedule work without a later explicit rollout
decision.

#### Scenario: Review completes successfully
- **WHEN** project and portfolio analysis returns feasible placements
- **THEN** all placements remain virtual and existing Org content is byte-for-byte unchanged
