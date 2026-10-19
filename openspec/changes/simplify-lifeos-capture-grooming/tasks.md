## 1. Characterize Safety Boundaries

- [ ] 1.1 Add ERT fixtures for a title-only captured task, each partially clarified task state, duplicate-title dependencies, and an interrupted clarification resumed from saved Org
- [ ] 1.2 Add ERT assertions that incomplete captures appear in Needs Grooming but remain absent from heuristic records and normalized solver input until canonical eligibility succeeds
- [ ] 1.3 Add read-only characterization tests proving queue refresh, next-answer inspection, and blocker navigation do not change authoritative Org content

## 2. One-Title Capture

- [ ] 2.1 Implement `my/lifeos-capture-task` to accept one non-blank title, create a top-level `TODO` `#task` with stable ID and empty canonical scaffold fields in `inbox.org`, save it, and show a clarify-later success message
- [ ] 2.2 Make blank input and cancellation leave `inbox.org` unchanged, including when the inbox file or heading insertion point must first be prepared
- [ ] 2.3 Bind the novice LifeOS capture path directly to `my/lifeos-capture-task` while retaining ordinary `org-capture` as an available advanced command
- [ ] 2.4 Add ERT coverage for exact prompt count, stored heading shape, stable identity after reopening, save completion, success messaging, blank input, and cancellation

## 3. Progressive Clarification

- [ ] 3.1 Implement one canonical next-task-decision function that skips valid values and orders structural repair, impact, priority, effort, work mode, and conditional waiting reason
- [ ] 3.2 Change `my/lifeos-groom-task` to request and commit at most one answer per invocation, save accepted progress, rerun canonical validation, and report the next answer or ready state
- [ ] 3.3 Implement first-effort handling that initializes invalid or missing `ORIGINAL_EFFORT` from the accepted `EFFORT` without replacing an existing valid original estimate
- [ ] 3.4 Add plain-language impact and priority choices that map to the canonical value constants and explain consequence versus urgency without changing planner semantics
- [ ] 3.5 Make cancellation and structural-error paths preserve the current unanswered value, avoid later prompts, and retain answers saved by prior invocations
- [ ] 3.6 Add ERT coverage for every decision transition, out-of-order existing values, one-prompt limits, restart/resume, cancellation, structural errors, effort initialization, and final eligibility

## 4. Guided Dependencies

- [ ] 4.1 Extend task dependency interaction with add and remove actions that display current blockers and eligible candidates by title rather than ID
- [ ] 4.2 Add project or file context to duplicate-title candidates while retaining stable IDs and canonical `depends-on` links in Org
- [ ] 4.3 Preserve existing target-eligibility, duplicate, and cycle checks and make failed or cancelled edits leave the task body unchanged
- [ ] 4.4 Add ERT coverage for unique and duplicate titles, add, remove, cancellation, ineligible targets, duplicates, cycles, saved links, and no exposed ID-entry prompt

## 5. Clarification Queue And Navigation

- [ ] 5.1 Extend typed Needs Grooming task records with the canonical next missing answer and render it in each incomplete task row without changing project rows
- [ ] 5.2 Add a task-level next-missing-answer command that reports one decision or structural repair and offers its clarification action
- [ ] 5.3 Add visit-blocker interaction that selects direct blockers by title, visits the authoritative Org heading, and handles the no-blocker case without moving point
- [ ] 5.4 Preserve ephemeral queue return context when visiting source or a blocker and add return-to-queue behavior that rebuilds records from current Org
- [ ] 5.5 Advertise source, clarify, blocker, return, refresh, help, and quit actions in the Needs Grooming mode with novice-readable labels and keybindings
- [ ] 5.6 Add ERT rendering and interaction coverage for next-answer rows, source visits, multiple blockers, stale return context, partial clarification, valid-task removal, and unchanged Org on read-only paths

## 6. User Guidance

- [ ] 6.1 Update Start Here and the capture workflow to lead with the direct capture keys, one title prompt, saved Inbox result, clarification queue, and one-answer example
- [ ] 6.2 Update task clarification and recovery guidance for next-answer order, stop/resume, cancellation, structural errors, and the distinction between visible incomplete work and schedulable work
- [ ] 6.3 Update dependency guidance to use add/remove and blocker navigation by task name, with Org IDs and link syntax confined to reference material
- [ ] 6.4 Update impact, priority, command, and keybinding reference pages to document canonical mappings and current non-solver semantics
- [ ] 6.5 Extend documentation-integrity expectations for the new interactive commands, direct capture binding, canonical values, local links, and interruption example

## 7. Verification

- [ ] 7.1 Run the LifeOS planning, forecast, solver, and documentation ERT suites and fix regressions without weakening canonical task validation
- [ ] 7.2 Exercise capture, immediate Emacs restart, repeated single-answer clarification, cancellation, duplicate-title dependency editing, blocker navigation, and queue return against representative Org files
- [ ] 7.3 Confirm incomplete tasks remain visible in Inbox and Needs Grooming while excluded from heuristic and solver input, then become eligible only after canonical validation succeeds
- [ ] 7.4 Confirm analytical and navigation paths preserve authoritative Org hashes and no queue, wizard-position, or readiness state is persisted outside Org
- [ ] 7.5 Run documentation-integrity checks, strict OpenSpec validation, and `git diff --check`
