## ADDED Requirements

### Requirement: Org-native manual hierarchy
LifeOS SHALL provide an Org-native user manual rooted at `~/Work/lifeos/docs/lifeos/index.org`. The LifeOS README at `~/Work/lifeos/README.md` SHALL remain a concise product and installation entry point that links to the manual, current change status, and retained developer references in dotfiles.

#### Scenario: User opens manual root
- **WHEN** the user opens `~/Work/lifeos/docs/lifeos/index.org`
- **THEN** the first screen offers goal-oriented paths for capturing and grooming, choosing work, creating a project, fixing red headings, understanding `UNKNOWN`, changing defaults, and reading technical details

#### Scenario: User opens root README
- **WHEN** a user reads `~/Work/lifeos/README.md`
- **THEN** they can identify what LifeOS is, how to begin installation or use, where the user manual lives, and which material is current or proposed without traversing the complete feature reference

### Requirement: Action-first workflow chapters
Every primary workflow chapter SHALL begin with a short ordered action path, followed by the expected result, a complete example, recovery guidance, a concise explanation, and links to deeper reference. Theory and implementation details MUST NOT precede the primary action path.

#### Scenario: Create and groom a project
- **WHEN** the user opens the create-a-project workflow
- **THEN** the chapter first tells them what command or keys to use, what prompts to answer, what success looks like, and how to repair red feedback before explaining effort envelopes or virtual work

#### Scenario: Fix a red heading
- **WHEN** the user opens diagnostic troubleshooting
- **THEN** the chapter provides a direct inspect-and-repair loop before listing diagnostic internals

### Requirement: Current task-state guide
The manual SHALL provide a decision guide for `TODO`, `NEXT`, `WAITING`, `SOMEDAY`, `DONE`, and `CANCELLED` that describes current validation, readiness, heuristic, and solver behavior without implying nonexistent prioritization or release semantics.

#### Scenario: Decide between TODO and NEXT
- **WHEN** a user asks whether `NEXT` receives higher planner priority
- **THEN** the guide states that both are active and allocatable, while `NEXT` is a dependency-guarded human workflow marker rather than a solver preference

#### Scenario: Wait for a known date
- **WHEN** a user cannot start work before a known date
- **THEN** the guide demonstrates `WAITING` with a parseable future `WAIT_UNTIL` and explains the solver and visible-heuristic behavior

#### Scenario: Wait for another task
- **WHEN** a task depends on another LifeOS task
- **THEN** the guide recommends modeling the `depends-on` relation and explains the current consequences of also placing the task in `WAITING`

#### Scenario: Exclude optional future work
- **WHEN** the user does not want work considered by planning
- **THEN** the guide explains that `SOMEDAY` is excluded and receives reduced metadata validation

### Requirement: Configuration guide
The manual SHALL explain where and how to edit each configuration layer, its precedence, whether it is fallback or authoritative policy, and how to reach it through the settings entry point.

#### Scenario: Change recurring defaults
- **WHEN** a user wants to alter ordinary sleep, reserve, safety, or travel policy
- **THEN** the guide directs them to recurring planning policy, shows a valid complete example, and distinguishes it from Elisp fallback values

#### Scenario: Override one project
- **WHEN** a user wants a project-specific supported override
- **THEN** the guide identifies the project property, its precedence, and the guided path to edit it

### Requirement: Progressive disclosure and bounded terminology
User workflow pages SHALL use user-language actions first, introduce only terms necessary for the current decision, and link technical concepts to reference chapters. Command symbols and property names SHALL appear as secondary reference when a guided command exists.

#### Scenario: User follows first successful workflow
- **WHEN** a new user follows Start Here
- **THEN** they can capture, groom, inspect, and choose one task without first learning solver protocol, project normalization, scenario schemas, or Z3 terminology

### Requirement: Examples include outcomes and recovery
Every core workflow SHALL include realistic Org or interaction examples, the expected visible result, and a recovery path for common invalid or unknown outcomes.

#### Scenario: Underspecified task example
- **WHEN** a workflow intentionally creates an incomplete task
- **THEN** it shows the resulting diagnostic, the exact remediation flow, and the expected valid state

#### Scenario: Underspecified project example
- **WHEN** a workflow intentionally creates an incomplete project
- **THEN** it shows the local project diagnostic, project grooming flow, and resulting definition status

### Requirement: Current, proposed, and historical material are distinct
Documentation navigation SHALL label implemented behavior, proposed changes, developer reference, and historical transcripts distinctly. Proposed OpenSpec requirements MUST NOT be presented as current user behavior until implemented.

#### Scenario: Read about project release gates before implementation
- **WHEN** a user follows current manual navigation while `add-project-release-dependencies` remains unimplemented
- **THEN** `NOT_BEFORE` and project dependency behavior is absent from current instructions or explicitly labeled proposed

### Requirement: Documentation integrity
Automated verification SHALL detect missing local manual links, references to nonexistent interactive commands, mismatched documented keybindings, and divergence between documented enum values and canonical code vocabularies.

#### Scenario: Command is renamed without updating documentation
- **WHEN** an interactive command referenced by the manual no longer exists
- **THEN** documentation verification fails with the affected manual location

#### Scenario: Local chapter link is broken
- **WHEN** an Org file link targets a missing local chapter or heading
- **THEN** documentation verification fails with the broken link source
