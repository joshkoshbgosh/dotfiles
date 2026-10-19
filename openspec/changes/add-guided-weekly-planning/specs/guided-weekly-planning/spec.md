## ADDED Requirements

### Requirement: Guided weekly planning uses an isolated draft
LifeOS SHALL provide a guided weekly-planning command that loads calendar commitments, recurring policy, and matching weekly policy into an in-memory draft for a selected week. Prompts SHALL use dates, times, modes, outcomes, and projects rather than requiring Org heading, table, property, or selector syntax. Draft edits MUST NOT modify authoritative Org or calendar source.

#### Scenario: Start a week with no weekly policy
- **WHEN** the user starts guided planning for a week with recurring policy and calendar commitments but no matching weekly heading
- **THEN** the draft begins with the effective recurring policy and visible calendar constraints without creating a heading in `planning.org`

#### Scenario: Cancel after several edits
- **WHEN** the user changes availability and intentions in the draft and then cancels
- **THEN** `planning.org`, task files, and calendar source remain byte-for-byte unchanged

### Requirement: Weekly availability is an exception overlay
LifeOS SHALL derive weekly availability by expanding recurring availability, subtracting all weekly `Remove` exception intervals per date and mode, and then unioning all weekly `Add` exception intervals per date and mode. Intervals SHALL be half-open; duplicate, adjacent, and same-operation overlapping intervals SHALL be canonicalized; and an add SHALL win over an overlapping removal for the same date and mode. Exceptions MUST affect only listed modes and MUST NOT replace unrelated recurring windows.

#### Scenario: Remove part of one recurring day
- **WHEN** recurring Tuesday Deep availability is `09:00` through `17:00` and the week removes Deep availability from `13:00` through `15:00`
- **THEN** effective Tuesday Deep availability is `09:00` through `13:00` and `15:00` through `17:00`, with other dates and modes unchanged

#### Scenario: Add overlaps a removal
- **WHEN** the same date and mode remove `13:00` through `17:00` and add `16:00` through `18:00`
- **THEN** the effective overlay removes `13:00` through `16:00` and includes `16:00` through `18:00` exactly once

#### Scenario: Modes share one physical interval
- **WHEN** one effective interval supports both Deep and Shallow work
- **THEN** it appears in each mode's capacity view but contributes only once to unique physical capacity

### Requirement: Availability exceptions have a canonical Org schema
A matching `#week` heading SHALL store guided availability changes in an `Availability exceptions` table with exactly `Operation`, `Date`, `Start`, `End`, and `Modes` columns. Operations MUST be `Add` or `Remove`; dates MUST lie within the selected week; times MUST define a non-empty interval; modes MUST use canonical values; and guided cross-midnight input SHALL serialize as dated rows that do not cross midnight.

#### Scenario: Valid guided exception is serialized
- **WHEN** the user adds Social availability from Friday 22:00 through Saturday 01:00 and confirms
- **THEN** LifeOS writes canonical Friday and Saturday `Add` rows whose union represents the requested interval

#### Scenario: Raw exception contains an unknown mode
- **WHEN** an exception row edited in Org names a mode outside the canonical vocabulary
- **THEN** policy validation rejects the row with its source and no guided confirmation overwrites it

### Requirement: Planner shows effective policy and precedence
Before confirmation, the planner SHALL show the exact effective availability, intentions, solver configuration, and source of each value. It SHALL explain that availability exceptions overlay recurring availability, a matching weekly `Intentions` table replaces recurring intentions as a whole, a matching weekly Solver configuration replaces recurring configuration as a whole, and supported project properties retain their existing more-specific precedence.

#### Scenario: Draft changes only availability
- **WHEN** the user adds an availability exception but does not edit inherited intentions
- **THEN** the preview labels intentions as inherited and confirmation does not create a weekly `Intentions` table

#### Scenario: Draft edits an inherited intention
- **WHEN** the user changes one intention inherited from recurring policy
- **THEN** the preview shows a complete weekly intention set and warns that the complete set will replace recurring intentions for that week

### Requirement: Intention outcomes are created through a selector builder
The guided planner SHALL create intentions through typed selector clauses for task tags, project tags, project IDs, task properties, project properties, work modes, calendar roles, and task source, combined with all, any, and not groups. It SHALL render the canonical restricted selector and a plain-language summary, reject unsupported or empty expressions, and preview matching explicit tasks, virtual project work, and timed calendar sources before accepting the intention.

#### Scenario: Build a project and calendar outcome
- **WHEN** the user chooses any of project tag `school` and calendar role `school`
- **THEN** the builder produces `(or (project-tag "school") (calendar-role "school"))` and previews both matching project work and timed school events

#### Scenario: Builder selection matches nothing
- **WHEN** a valid selector currently matches no task, virtual work, or timed calendar source
- **THEN** the planner keeps the selector valid but immediately displays that it has no current matches

### Requirement: Intention bounds are explained and validated
The planner SHALL describe minimum as a soft desired floor, target as the preferred allocation, and maximum as a soft desired ceiling. Each value SHALL be an optional non-negative `H:MM` duration; zero SHALL be distinct from omission; and supplied pairs MUST satisfy minimum less than or equal to target less than or equal to maximum. A shortfall or excess MUST be reported as planning pressure and MUST NOT by itself make hard schedule feasibility false.

#### Scenario: Maximum is below target
- **WHEN** the user enters a target of `6:00` and a maximum of `4:00`
- **THEN** the planner rejects the bounds immediately and explains the required order

#### Scenario: Mandatory work exceeds a maximum
- **WHEN** fixed or mandatory matching work allocates more than an intention maximum but all hard scheduling constraints fit
- **THEN** the planner reports maximum excess while preserving the feasible hard-schedule result

### Requirement: Calendar credit and overlapping intentions are explicit
Timed calendar event minutes clipped to the selected week SHALL credit every intention whose selector matches the event's canonical calendar role. All-day events, generated travel, and remote setup MUST NOT credit intentions even when they reduce capacity. A task, virtual work item, or credited event matching multiple intentions SHALL independently credit each matching row while consuming physical time only once; intention rows MUST NOT be summed as either total demand or total progress.

#### Scenario: One event matches two intentions
- **WHEN** a two-hour timed event matches two intention selectors
- **THEN** each row receives two hours of credit, the overlap is disclosed, and usable physical capacity is reduced by only two hours

#### Scenario: All-day event has a matching role
- **WHEN** an all-day event blocks availability and its role matches an intention
- **THEN** it reduces usable capacity according to calendar policy and contributes zero intention credit

### Requirement: Draft feedback is immediate and evidence-aware
After every draft edit, LifeOS SHALL synchronously refresh validation diagnostics, effective availability, unique and per-mode usable capacity, blocked time, intention gaps and overlaps, and heuristic placement pressure from the draft. It SHALL invalidate solver evidence for older draft identities, debounce a new solver request, reject stale responses, and label evidence as `RUNNING`, `CURRENT`, `STALE`, `LOCAL ONLY`, or `UNAVAILABLE`. Capacity arithmetic and heuristic output MUST NOT be presented as solver proof.

#### Scenario: Availability is removed while a solve is running
- **WHEN** the user removes availability after a solver request has started
- **THEN** capacity and heuristic pressure update immediately, the old evidence becomes stale, and its eventual response cannot become current for the new draft

#### Scenario: Solver is unavailable
- **WHEN** the solver cannot analyze an otherwise valid draft
- **THEN** immediate capacity and heuristic feedback remain visible and feasibility is labeled `UNAVAILABLE` rather than inferred

### Requirement: Confirmation is the only write boundary
LifeOS SHALL enable confirmation only for a fully valid reviewed draft. On confirmation it MUST verify that captured Org and calendar inputs have not changed, serialize canonical weekly policy, round-trip that serialization through authoritative parsers, show the destination and changes, and apply one Org buffer transaction. Cancellation, stale inputs, parse failure, or write failure MUST leave authoritative source unchanged.

#### Scenario: Source changes before confirmation
- **WHEN** `planning.org` changes after the draft was loaded and before confirmation
- **THEN** LifeOS refuses the write, marks the draft stale, and requires refresh and review

#### Scenario: Confirm a valid draft
- **WHEN** the user reviews and confirms a valid draft against unchanged sources
- **THEN** only the corresponding policy under the selected week is written to `planning.org`, and task and calendar files remain unchanged

### Requirement: Raw policy editing remains available
LifeOS SHALL retain an advanced command that visits canonical recurring and weekly Org policy and SHALL continue to parse valid raw `Intentions`, `Availability exceptions`, and Solver configuration tables with the same semantics as guided output. The guided workflow MUST NOT hide raw source, invent a second persisted representation, or rewrite unrelated raw policy.

#### Scenario: Advanced user inspects generated policy
- **WHEN** the user chooses raw policy editing from the planner or settings
- **THEN** Emacs visits the authoritative location in `planning.org` and identifies the active precedence rules
