## ADDED Requirements

### Requirement: Canonical project diagnostics
The system SHALL expose structured diagnostics for every explicit `#project` using the same validation rules and values used to derive the project's definition status. Inventory construction, point-level validation, grooming, reports, and overlays MUST consume this canonical diagnostic path.

#### Scenario: Incomplete project at point
- **WHEN** point is on an explicit project missing a valid deadline or project effort
- **THEN** point-level validation returns the same diagnostic codes and messages used to classify the project `INCOMPLETE`

#### Scenario: Complete project remains unchanged
- **WHEN** an existing project is valid under the current definition rules
- **THEN** introducing point-level project diagnostics does not change its commitment, definition status, effort accounting, or proof inputs

### Requirement: Immediate local project feedback
An Org buffer with LifeOS diagnostics enabled SHALL show project definition errors locally without requiring the user to open Portfolio Review. Heading-local errors MUST become visible after the edit feedback cycle independently of solver completion.

#### Scenario: User creates an underspecified project
- **WHEN** a user adds `#project` to a heading and leaves required values empty
- **THEN** the heading displays an error count whose help text names the missing or invalid project fields

#### Scenario: Solver evidence is pending
- **WHEN** local project metadata is invalid while project or solver analysis is pending
- **THEN** local definition diagnostics are still displayed and cached metrics are visually distinguished from them

### Requirement: Unified diagnostic navigation and explanation
Project diagnostics SHALL participate in the same next/previous diagnostic navigation as task diagnostics. Explain-at-point SHALL present actionable project diagnostics before project metrics and SHALL identify the command or edit that resolves each finding.

#### Scenario: Navigate from a task error to a project error
- **WHEN** a buffer contains a task diagnostic followed by a project diagnostic
- **THEN** next-diagnostic visits both headings in source order and wraps consistently

#### Scenario: Explain an incomplete project
- **WHEN** the user invokes explain-at-point on an incomplete project
- **THEN** the explanation lists each definition error, a remediation path, and then any available effort or forecast metrics

### Requirement: Type-aware grooming report
Needs Grooming SHALL classify explicit projects as projects and executable work as tasks. It MUST NOT run task schema validation against a project heading, and project records SHALL link to the project source and project grooming flow.

#### Scenario: Project and task both need grooming
- **WHEN** the selected scope contains one incomplete project and one invalid task
- **THEN** the report shows one project record with project diagnostics and one task record with task diagnostics

#### Scenario: Project is not reported as missing task tag
- **WHEN** an active explicit project has no `#task` tag
- **THEN** Needs Grooming does not emit `Missing #task` for the project heading

### Requirement: Grooming concludes with project validation
Project grooming SHALL validate the resulting project immediately and report either success or the remaining actionable project diagnostics. Cancellation or invalid input MUST preserve pre-command source values except for changes the user already explicitly confirmed.

#### Scenario: Grooming completes all required fields
- **WHEN** the user supplies valid project metadata through project grooming
- **THEN** the command reports that project metadata is valid and the local error indicator clears

#### Scenario: Descendant problem remains
- **WHEN** project metadata is valid but an active descendant is not a valid executable task
- **THEN** grooming reports the unresolved descendant finding and provides a source or grooming path

### Requirement: Standard project property completion
Every enumerated project property SHALL expose allowed values through standard Org property editing, and grooming, validation, scenarios, and completion MUST obtain those values from one canonical vocabulary definition.

#### Scenario: Complete default work mode
- **WHEN** the user edits `DEFAULT_WORK_MODE` with a standard Org property command
- **THEN** completion offers exactly the supported LifeOS work modes

#### Scenario: Complete estimate confidence
- **WHEN** the user edits `ESTIMATE_CONFIDENCE` with a standard Org property command
- **THEN** completion offers `Low`, `Medium`, and `High` from the same source used by validation

#### Scenario: Free-form duration remains free-form
- **WHEN** the user edits `PROJECT_EFFORT` or `PLANNING_CHUNK`
- **THEN** the system validates the duration format without presenting a misleading closed enum

### Requirement: Analysis remains read-only
Local and global diagnostics, diagnostic navigation, explanations, and reports MUST NOT modify authoritative Org source. Only explicit scaffolding, grooming, and confirmed editing commands may write project metadata.

#### Scenario: Refresh project diagnostics
- **WHEN** diagnostics refresh for an incomplete project
- **THEN** the Org buffer's source text remains byte-for-byte unchanged
