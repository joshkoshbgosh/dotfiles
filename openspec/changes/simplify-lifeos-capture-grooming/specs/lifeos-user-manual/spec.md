## MODIFIED Requirements

### Requirement: Org-native manual hierarchy
LifeOS SHALL provide an Org-native user manual rooted at `~/Work/lifeos/docs/lifeos/index.org`. The LifeOS README at `~/Work/lifeos/README.md` SHALL remain a concise product and installation entry point that links to the manual, current change status, and retained developer references in dotfiles.

#### Scenario: User opens manual root
- **WHEN** the user opens `~/Work/lifeos/docs/lifeos/index.org`
- **THEN** the first screen offers goal-oriented paths for capturing a thought, clarifying inbox work one answer at a time, choosing work, creating a project, fixing red headings, understanding `UNKNOWN`, changing defaults, and reading technical details

#### Scenario: User opens root README
- **WHEN** a user reads `~/Work/lifeos/README.md`
- **THEN** they can identify what LifeOS is, how to begin installation or use, where the user manual lives, and which material is current or proposed without traversing the complete feature reference

### Requirement: Action-first workflow chapters
Every primary workflow chapter SHALL begin with a short ordered action path, followed by the expected result, a complete example, recovery guidance, a concise explanation, and links to deeper reference. Theory and implementation details MUST NOT precede the primary action path.

#### Scenario: Capture and clarify a task
- **WHEN** the user opens the capture-and-clarify workflow
- **THEN** the chapter first gives the capture command or keys, asks only for a title, shows where the saved inbox task and clarification queue appear, and demonstrates answering one next question before explaining task properties or solver eligibility

#### Scenario: Create and groom a project
- **WHEN** the user opens the create-a-project workflow
- **THEN** the chapter first tells them what command or keys to use, what prompts to answer, what success looks like, and how to repair red feedback before explaining effort envelopes or virtual work

#### Scenario: Fix a red heading
- **WHEN** the user opens diagnostic troubleshooting
- **THEN** the chapter provides a direct inspect-and-repair loop before listing diagnostic internals

### Requirement: Progressive disclosure and bounded terminology
User workflow pages SHALL use user-language actions first, introduce only terms necessary for the current decision, and link technical concepts to reference chapters. Command symbols, Org IDs, link syntax, and property names SHALL appear as secondary reference when a guided command exists.

#### Scenario: User follows first successful workflow
- **WHEN** a new user follows Start Here
- **THEN** they can capture a title, find it in Needs Grooming, answer its next clarification question, and choose one valid task without first learning Org heading syntax, property names, dependency IDs, solver protocol, project normalization, scenario schemas, or Z3 terminology

#### Scenario: User adds a dependency
- **WHEN** a novice follows the task dependency workflow
- **THEN** the primary path tells them how to select a blocker by task name while Org IDs and `depends-on` syntax appear only in deeper reference

### Requirement: Examples include outcomes and recovery
Every core workflow SHALL include realistic Org or interaction examples, the expected visible result, and a recovery path for common invalid, interrupted, or unknown outcomes.

#### Scenario: Underspecified task example
- **WHEN** the capture workflow intentionally creates an incomplete task
- **THEN** it shows the saved Inbox item, its Needs Grooming row, its exclusion from schedulable work, the exact next-answer flow, cancellation behavior, and the expected valid state after clarification

#### Scenario: Interrupted clarification example
- **WHEN** the user stops after answering only impact or restarts Emacs before the next answer
- **THEN** the manual shows that the accepted Org value remains saved and that clarification resumes at the next missing answer

#### Scenario: Underspecified project example
- **WHEN** a workflow intentionally creates an incomplete project
- **THEN** it shows the local project diagnostic, project grooming flow, and resulting definition status
