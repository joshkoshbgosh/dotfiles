## Why

LifeOS currently makes a newly captured thought pass through Org syntax, tagging,
metadata prompts, and diagnostics before it becomes safely actionable. That
front-loads executive-function work and allows captured but incomplete items to
fall out of the user's normal decision surfaces.

## What Changes

- Add one-step LifeOS capture that requires only a title and creates a durable,
  visible inbox item with stable identity.
- Keep incomplete captures visible in a dedicated clarification queue without
  presenting them as solver-ready work.
- Replace all-at-once task grooming with progressive clarification that asks only
  for information needed by the next planning decision and can be stopped and
  resumed without losing prior answers.
- Add guided dependency selection by task name so users do not manipulate Org IDs
  or custom link syntax directly.
- Present priority and impact with plain-language decision guidance while retaining
  their current source fields and solver semantics.
- Add task-level commands to identify the next missing answer, navigate to a
  blocker, and return to the clarification queue.
- Update beginner and recovery guidance around capture, clarification, and the
  distinction between visible inbox work and schedulable work.

## Capabilities

### New Capabilities

- `progressive-task-intake`: One-step capture, persistent incomplete-item
  visibility, resumable clarification, and guided dependency editing.

### Modified Capabilities

- `lifeos-user-manual`: Start Here and task workflows change from manual heading
  insertion plus all-at-once grooming to one-step capture and progressive
  clarification.

## Impact

- Emacs Org capture templates and LifeOS capture, scaffolding, grooming,
  dependency-link, diagnostic, and report commands.
- Inbox and Needs Grooming presentation, keybindings, source navigation, and
  tests for interrupted or partial clarification.
- Current LifeOS user documentation and documentation-integrity tests.
- No solver protocol change is required; incomplete items remain excluded from
  solver input but are never hidden from the user.
