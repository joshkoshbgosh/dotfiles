## MODIFIED Requirements

### Requirement: Configuration guide
The manual SHALL explain where and how to edit each configuration layer, its precedence, whether it is an overlay, a complete replacement, a fallback, or authoritative policy, and how to reach it through the settings entry point. Weekly guidance SHALL lead with guided planning while retaining canonical Org schemas and raw editing commands as advanced reference.

#### Scenario: Change recurring defaults
- **WHEN** a user wants to alter ordinary sleep, reserve, safety, travel, or availability policy
- **THEN** the guide directs them to recurring planning policy, shows a valid complete example, and distinguishes it from Elisp fallback values

#### Scenario: Change one week
- **WHEN** a user wants different availability or outcomes for one week
- **THEN** the guide starts with guided weekly planning and explains availability overlays separately from complete weekly intention and Solver configuration replacements

#### Scenario: Override one project
- **WHEN** a user wants a project-specific supported override
- **THEN** the guide identifies the project property, its precedence, and the guided path to edit it

## ADDED Requirements

### Requirement: Weekly planning uses progressive disclosure
Weekly-planning guidance SHALL use user-language actions before command symbols,
heading names, property names, table schemas, or selector expressions. It SHALL
retain canonical raw policy details as secondary reference for advanced editing
and recovery.

#### Scenario: Advanced user needs raw weekly policy
- **WHEN** a user follows the advanced link from guided weekly planning
- **THEN** the manual shows the canonical headings, exception and replacement table schemas, selectors, validation rules, and precedence

### Requirement: Guided weekly-planning chapter
The manual SHALL provide an action-first guided weekly-planning chapter covering selection of the week, calendar review, availability additions and removals, intended outcomes, selector construction, minimum/target/maximum choices, capacity and feasibility feedback, preview, confirmation, and cancellation. It SHALL show expected results and recovery for invalid bounds, selectors with no matches, overlapping exceptions, stale sources, and unavailable solver evidence.

#### Scenario: User plans an exceptional week
- **WHEN** a user follows the chapter to remove one afternoon, add one evening, and prioritize a project outcome
- **THEN** they can complete and confirm the plan without manually entering Org table or selector syntax

#### Scenario: User cancels at confirmation
- **WHEN** the user decides the effective-week preview is wrong
- **THEN** the chapter states that cancellation writes nothing and directs them back to the relevant draft step

### Requirement: Manual defines allocation and overlap semantics
The manual SHALL define minimum as a soft floor, target as the preferred allocation, maximum as a soft ceiling, and missing bounds as unconstrained preferences. It SHALL explain eligible calendar credit, distinguish capacity blocking from intention credit, and state that overlapping selectors independently credit rows while shared work consumes physical capacity once and row totals are not additive.

#### Scenario: Reader compares two overlapping outcomes
- **WHEN** one task matches both a project outcome and a Deep-work outcome
- **THEN** the example shows the task credited to both rows, scheduled once, and excluded from any summed intention total

#### Scenario: Reader interprets an exceeded maximum
- **WHEN** mandatory work exceeds a soft maximum
- **THEN** the manual distinguishes maximum excess from hard infeasibility and explains the remediation choices
