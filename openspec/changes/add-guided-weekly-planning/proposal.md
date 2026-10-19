## Why

Weekly planning currently requires exact Org headings, complete replacement
tables, duration syntax, and raw intention selectors. This makes expressing a
simple weekly exception or outcome depend on configuration-file accuracy rather
than the user's planning judgment.

## What Changes

- Add a guided weekly-planning command that starts from calendar commitments and
  recurring policy, then asks for availability exceptions and a small set of
  intended outcomes in plain language.
- Show usable capacity by work mode and immediate feasibility feedback while the
  weekly plan is being edited.
- Add additive and subtractive weekly availability exceptions so changing one day
  does not require copying the complete recurring table.
- Add guided intention creation for projects, tasks, tags, work modes, and calendar
  roles without requiring users to write selector expressions.
- Define user-facing semantics for minimum, target, maximum, overlap, calendar
  credit, and unmet intentions.
- Preview the exact effective week and source precedence before writing confirmed
  policy changes to `planning.org`.
- Preserve an advanced path for editing and inspecting canonical Org tables and
  selectors directly.

## Capabilities

### New Capabilities

- `guided-weekly-planning`: Conversational weekly setup, exception overlays,
  intention construction, capacity preview, and confirmed source updates.

### Modified Capabilities

- `lifeos-configuration-guidance`: Weekly policy gains guided editing and
  exception overlays instead of requiring complete-table replacement for every
  variation.
- `selector-only-intentions`: Intention semantics and selectors become available
  through guided creation while preserving selector-based accounting.
- `lifeos-user-manual`: Weekly planning guidance changes from raw table editing to
  the guided workflow, with raw syntax retained as reference.

## Impact

- Planning Org schema for weekly availability exceptions and canonical intention
  rows, including migration and precedence rules.
- Emacs weekly-planning UI, selector builder, parser, effective-policy rendering,
  diagnostics, and capacity feedback.
- Heuristic and solver request invalidation while editing previews, without
  changing authoritative source before confirmation.
- ERT, solver integration, documentation, and representative-week tests.
