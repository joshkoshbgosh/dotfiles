## Context

LifeOS currently has canonical task diagnostics, safe task scaffolding, a Needs
Grooming report, and solver eligibility that rejects invalid executable tasks.
The difficult path is interaction: capture exposes general Org concepts, task
grooming asks for the complete schema in one session, dependency links expose
IDs, and reports explain errors rather than guiding the next small decision.

The primary user is a novice Emacs user with severe ADHD. Capture therefore must
survive interruption after one meaningful input, and clarification must remain
useful when the user can answer only one question. Org files remain the
authoritative record. Existing task validation and solver normalization remain
the authority for readiness; the interaction layer must not create a second
readiness model.

## Goals / Non-Goals

**Goals:**

- Capture a durable inbox task after entering only a non-blank title.
- Keep every incomplete active task discoverable without admitting it to solver
  input.
- Turn task grooming into a resumable sequence of one small decision at a time.
- Hide Org IDs, link syntax, and property names behind guided task-name choices.
- Explain impact and priority in decision language while preserving the existing
  `IMPACT` and Org `PRIORITY` values and their planner semantics.
- Make the next clarification step, blockers, source, and return path obvious to
  a novice without requiring command-name recall.

**Non-Goals:**

- Changing task schema, task-state meanings, ordering heuristics, or solver
  protocol.
- Making an incomplete task schedulable or silently supplying semantic defaults.
- Replacing Org with a database or persisting queue/progress state outside Org.
- Redesigning project grooming or project dependency semantics.
- Inferring dependencies, impact, priority, effort, or work mode from title text.

## Decisions

### Capture directly to an incomplete but identified Org task

A dedicated `my/lifeos-capture-task` command will ask only for a title and create
a top-level `TODO` `#task` in `inbox.org`. It will assign an Org `ID`, create the
existing empty scaffold fields, save the file, and report that the item is safe
in Inbox and can be clarified later. Blank input or cancellation creates
nothing.

This uses the existing incomplete-task representation instead of introducing a
new capture state. A fully populated template was rejected because it moves
planning decisions into the interruption-sensitive capture moment. A plain Org
heading without task identity was rejected because it can disappear from task
diagnostics and cannot be referenced reliably.

### Derive clarification state from canonical diagnostics and Org values

No wizard cursor or completion flag will be stored. Clarification will inspect
the current heading's Org values and canonical diagnostics each time. The fixed
decision order will be structural validity, impact, priority, effort, work mode,
and a waiting reason when the state is `WAITING`. Already valid answers are
skipped. `ORIGINAL_EFFORT` is initialized from the first accepted effort by the
existing rule rather than becoming another user question.

This makes interruption and resumption automatic: committed answers survive in
Org, and the next invocation recomputes the next missing answer. Persisting a
wizard step was rejected because it could disagree with manual Org edits or
validation changes. Asking every missing field in one invocation was rejected
because cancellation late in the sequence makes progress and source mutation
hard to understand.

### Commit at most one planning decision per clarification invocation

`my/lifeos-groom-task` will remain the familiar entry point but become
progressive. Each invocation presents only the next unresolved decision, writes
and saves that accepted answer, validates again, and says either what remains or
that the task is ready. Cancellation leaves the current decision unchanged;
answers accepted during earlier invocations remain authoritative.

Structural problems such as a task with TODO descendants are not coerced into a
property prompt. The command presents the specific repair action and leaves the
source unchanged. A multi-page transient was considered, but one standard Emacs
minibuffer decision at a time has fewer controls to learn and is easier to
resume.

### Use explanatory labels mapped to canonical values

Impact choices will explain outcome magnitude and map exactly to `High`,
`Medium`, or `Low`. Priority choices will explain urgency/order and map exactly
to Org priorities `A`, `B`, `C`, or `D`. Prompts and help will explicitly say
that impact is consequence and priority is urgency/order; neither invents a new
solver guarantee. Canonical constants remain the source for stored values,
validation, and generic Org completion.

Changing stored labels was rejected because it would migrate existing Org data
and solver inputs. Showing only bare enum letters and property names was rejected
because it requires schema recall and does not help a novice make the decision.

### Edit dependencies through task-name selection

The guided dependency command will show current blockers and offer add or remove
actions. Candidates will be displayed by task title, with project or file
context when titles collide; IDs remain internal values. Add will retain current
eligibility, duplicate, and cycle checks. Remove will delete only the selected
current task's direct `depends-on` link. Both actions will save only after a
confirmed valid selection.

Free-form ID entry was rejected as error-prone. Storing a title instead of an ID
was rejected because titles are mutable and non-unique. The authoritative Org
body therefore retains the existing `depends-on` ID link syntax.

### Make Needs Grooming the persistent clarification queue

Needs Grooming remains a derived, read-only view over agenda Org files. Task rows
will identify the next missing answer and expose direct actions to visit source,
clarify, visit a blocker, and return to the refreshed queue. A source visit will
record only an ephemeral return marker/window context; it will not mark the task
complete or alter Org. Completing one answer and returning rebuilds the queue so
the row either shows the next answer or disappears when valid.

A separate inbox database or dismissed-item list was rejected because it would
compete with Org authority. Automatically opening the queue after capture was
rejected because capture must remain an interruption-safe off-ramp rather than
forcing immediate planning.

### Preserve the current solver boundary

The solver and heuristic paths continue to consume only tasks accepted by
canonical eligibility. Captured tasks with empty required values remain visible
in Inbox, diagnostics, and Needs Grooming, but are absent from normalized solver
task input. Tests will assert both sides of this boundary. No interaction command
may make a task appear ready without canonical validation succeeding.

## Risks / Trade-offs

- [Risk] A fixed question order may not match every user's preferred planning
  order. -> Mitigation: skip every already-valid value, allow ordinary Org edits,
  and keep order in one named function covered by tests.
- [Risk] Two tasks can have the same title. -> Mitigation: show project or file
  context for disambiguation while retaining stable IDs internally.
- [Risk] Saving each accepted answer can expose partially clarified data to other
  readers. -> Mitigation: partial data is already a valid Org state and canonical
  eligibility continues to exclude it from solver input.
- [Risk] Reusing `my/lifeos-groom-task` changes an established command from a
  complete wizard to a single-step action. -> Mitigation: preserve the command
  name, document the new repeatable behavior, and show the next action after
  every invocation.
- [Risk] Queue return context can become stale if a source buffer changes. ->
  Mitigation: treat return context as ephemeral and always rebuild records from
  current Org on return.
- [Risk] Plain-language labels could imply semantics not implemented by the
  planner. -> Mitigation: map labels to canonical values and test documentation
  against the current priority, impact, and solver behavior.

## Migration Plan

1. Add characterization tests for current scaffold, validation, queue, dependency,
   and solver-exclusion behavior.
2. Add the dedicated capture command and binding while retaining ordinary
   `org-capture` as an advanced command.
3. Replace the all-at-once task grooming body with diagnostic-driven single-step
   clarification; existing valid task data requires no migration.
4. Extend dependency and queue interactions without changing stored link syntax.
5. Update the manual and documentation-integrity expectations with the same
   command and binding names.
6. Roll back by restoring the prior command implementations and binding. Org data
   remains compatible because the change adds no new persisted schema.

## Open Questions

None. Implementation may choose exact minibuffer wording, but it must preserve
the required decision meanings, one-decision interaction, and canonical values.
