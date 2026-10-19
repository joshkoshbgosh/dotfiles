## ADDED Requirements

### Requirement: One-title durable task capture
LifeOS SHALL provide a dedicated task-capture command that asks for exactly one
required user value, a non-blank title. On acceptance it SHALL create a top-level
`TODO` `#task` in `inbox.org`, assign a stable Org `ID`, create the existing task
scaffold fields without invented planning answers, save the Org file, and report
that the task is in Inbox and can be clarified later.

#### Scenario: Capture succeeds after one answer
- **WHEN** the user invokes task capture, enters `Book dentist`, and confirms the title
- **THEN** `inbox.org` contains a saved top-level `TODO` task named `Book dentist` with `#task`, a non-empty unique `ID`, and empty required planning fields without any further prompt

#### Scenario: Capture is cancelled
- **WHEN** the user cancels the title prompt or submits a blank title
- **THEN** LifeOS creates no heading, changes no Org file, and reports that nothing was captured

#### Scenario: Emacs stops after capture
- **WHEN** capture returns success and Emacs exits before any clarification command is run
- **THEN** reopening `inbox.org` shows the captured task with the same Org `ID`

### Requirement: Incomplete captures remain visible but unschedulable
LifeOS SHALL include every active captured task that fails canonical task
validation in Needs Grooming and SHALL identify its next missing answer. The
heuristic and solver normalization paths MUST exclude that task until canonical
task eligibility succeeds. Queue inclusion and solver exclusion SHALL be derived
from authoritative Org content rather than a separate completion flag.

#### Scenario: Fresh capture appears in clarification queue
- **WHEN** a newly captured task has an ID but has no impact, priority, effort, or work mode
- **THEN** Needs Grooming shows one source-navigable task row and names impact as its next missing answer

#### Scenario: Fresh capture is excluded from planning
- **WHEN** heuristic or solver input is built while that newly captured task remains incomplete
- **THEN** the task is absent from normalized schedulable task input while remaining present in `inbox.org` and Needs Grooming

#### Scenario: Canonical validation becomes successful
- **WHEN** the task has valid values for every requirement of its current task state and has no structural task error
- **THEN** the task disappears from Needs Grooming and becomes eligible under the unchanged canonical task-eligibility rules

### Requirement: Progressive clarification asks one decision at a time
Task clarification SHALL derive the next unresolved decision from current Org
content and canonical diagnostics in this order: structural validity, impact,
priority, effort, work mode, then a waiting reason when the task is `WAITING`.
Each invocation MUST request at most one planning answer, skip valid existing
answers, save an accepted answer immediately, rerun canonical validation, and
state either the next missing answer or that the task is ready.

#### Scenario: Clarify a fresh task once
- **WHEN** the user invokes task clarification on a fresh captured `TODO` task and accepts an impact choice
- **THEN** LifeOS stores only that impact answer, saves the Org file, does not prompt for priority in the same invocation, and reports priority as the next missing answer

#### Scenario: Resume after interruption
- **WHEN** impact and priority were accepted in earlier invocations and the user invokes clarification after restarting Emacs
- **THEN** LifeOS reads those answers from Org and prompts only for effort

#### Scenario: Cancel the current answer
- **WHEN** the user cancels a clarification prompt
- **THEN** the property addressed by that prompt remains unchanged, no later question is asked, and answers saved by prior invocations remain intact

#### Scenario: Existing valid answers are out of sequence
- **WHEN** a task already has valid effort and work mode but lacks impact and priority
- **THEN** clarification asks for impact first, then priority on a later invocation, and never asks again for the already-valid effort or work mode

#### Scenario: Structural error precedes metadata
- **WHEN** clarification is invoked on a `#task` with an active TODO descendant
- **THEN** LifeOS requests no metadata answer, leaves Org unchanged, and names the action for breaking down the aggregate or removing task classification

### Requirement: Effort initialization does not add a second question
LifeOS SHALL treat the first accepted total effort as one decision. When clarification accepts the first valid total effort for a task whose
`ORIGINAL_EFFORT` is missing or invalid, LifeOS SHALL write the same value to
`EFFORT` and `ORIGINAL_EFFORT` as one planning decision. It MUST preserve an
already valid `ORIGINAL_EFFORT`.

#### Scenario: First effort estimate
- **WHEN** effort is the next missing answer, `ORIGINAL_EFFORT` is empty, and the user accepts `0:45`
- **THEN** LifeOS stores `0:45` in both `EFFORT` and `ORIGINAL_EFFORT` without a second prompt

#### Scenario: Revised effort with original retained
- **WHEN** effort is invalid but `ORIGINAL_EFFORT` already contains valid value `1:00` and the user accepts effort `1:30`
- **THEN** LifeOS stores `1:30` in `EFFORT` and leaves `ORIGINAL_EFFORT` equal to `1:00`

### Requirement: Impact and priority use plain-language guidance
Clarification SHALL present impact as consequence and priority as urgency or
execution order. Impact choices SHALL map exactly to canonical values `High`,
`Medium`, and `Low`; priority choices SHALL map exactly to Org values `A`, `B`,
`C`, and `D`. Guidance MUST NOT claim that `NEXT` or a priority value provides a
solver preference that the current planner does not implement.

#### Scenario: Choose impact without property knowledge
- **WHEN** impact is the next missing answer
- **THEN** the prompt distinguishes major outcome, useful progress, and maintenance or convenience choices and stores the selected canonical `IMPACT` value

#### Scenario: Choose priority without Org syntax knowledge
- **WHEN** priority is the next missing answer
- **THEN** the prompt distinguishes must be handled first, important soon, normal, and low urgency choices and stores the corresponding Org priority `A`, `B`, `C`, or `D`

#### Scenario: Inspect clarification help
- **WHEN** a user asks what impact and priority mean
- **THEN** LifeOS explains that impact describes consequence, priority describes urgency or order, and canonical solver behavior remains unchanged

### Requirement: Dependencies are edited by task name
LifeOS SHALL provide guided dependency editing that lists the current task's
direct blockers and offers add and remove actions using task titles. Duplicate
titles MUST include project or file context sufficient to select one without
reading or entering an Org ID. Accepted edits SHALL retain stable IDs and the
existing `depends-on` link syntax in authoritative Org.

#### Scenario: Add a blocker by unique title
- **WHEN** the user chooses add and selects `Submit insurance form` from task-name completion
- **THEN** LifeOS writes one direct `depends-on` link containing that task's stable ID and displayed title without prompting for an ID or link syntax

#### Scenario: Disambiguate duplicate titles
- **WHEN** two eligible blocker candidates have the same title
- **THEN** completion displays distinguishing project or file context for both candidates and stores the ID of the selected task

#### Scenario: Reject unsafe dependency
- **WHEN** the selected blocker is already a direct dependency, is ineligible under existing dependency-target rules, or would create a cycle
- **THEN** LifeOS explains the specific conflict and leaves Org unchanged

#### Scenario: Remove a blocker by title
- **WHEN** the user chooses remove and selects one of the current task's displayed blockers
- **THEN** LifeOS removes only that direct dependency link, saves the Org file, and does not require the blocker ID

#### Scenario: Cancel dependency editing
- **WHEN** the user cancels the action or task selection
- **THEN** LifeOS leaves the current task body and all dependency links unchanged

### Requirement: Task-level clarification navigation
LifeOS SHALL provide task-level commands to identify the next missing answer,
visit a selected direct blocker, and return to a refreshed Needs Grooming queue.
The commands SHALL use task titles and action language in prompts and messages;
command symbols and Org property names MUST NOT be required knowledge.

#### Scenario: Ask for the next missing answer
- **WHEN** the user invokes next-missing-answer on an incomplete task
- **THEN** LifeOS names one next decision or structural repair and offers the corresponding clarification action

#### Scenario: Visit one of several blockers
- **WHEN** the current task has multiple direct blockers and the user invokes visit-blocker
- **THEN** LifeOS offers blocker titles, visits the selected authoritative Org heading, and preserves a return path to the queue

#### Scenario: Task has no direct blocker
- **WHEN** the user invokes visit-blocker on a task without direct dependencies
- **THEN** LifeOS reports that no blocker is recorded and does not move point or modify Org

#### Scenario: Return after one clarification answer
- **WHEN** the user reached a task from Needs Grooming, accepts one clarification answer, and invokes return-to-queue
- **THEN** LifeOS rebuilds Needs Grooming from current Org and either shows the task's next missing answer or omits the now-valid task

### Requirement: Clarification views do not compete with Org authority
LifeOS SHALL keep Org as the sole authority for task readiness. Needs Grooming, next-answer inspection, blocker navigation, and diagnostic refresh
MUST be read-only with respect to authoritative Org. Only explicit capture,
accepted clarification answers, and confirmed dependency edits may write task
content. LifeOS MUST NOT persist queue dismissal, wizard position, or readiness
outside Org.

#### Scenario: Refresh the queue repeatedly
- **WHEN** Needs Grooming is refreshed twice without an accepted edit between refreshes
- **THEN** authoritative Org files remain byte-for-byte unchanged and both refreshes derive the same task readiness from current Org

#### Scenario: Manual Org edit changes the next answer
- **WHEN** a user fills the currently missing property with a valid value using ordinary Org editing
- **THEN** the next queue refresh and clarification invocation skip that answer without requiring workflow-state repair
