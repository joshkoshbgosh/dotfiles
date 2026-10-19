## Why

LifeOS can calculate placements and test scenarios, but every answer is read-only
and ephemeral. Users cannot manipulate one coherent proposed schedule, see the
consequences immediately, and explicitly accept or reject it before it becomes a
plan.

## What Changes

- Add a schedule-draft workbench that presents one complete candidate future plan
  derived from current tasks, projects, calendar constraints, availability,
  intentions, and the currently accepted plan.
- Let users place proposed work at exact times, exclude it from the candidate,
  apply draft-only estimates, undo draft edits, and see why work was placed or
  omitted.
- Present the candidate in one keyboard-first day-by-day workbench with explicit
  current-plan deltas, separate omissions and consequences, block drilldowns, and
  a complete-plan acceptance review.
- Recompute feasibility in the background after draft changes and summarize
  deadline, safety, intention, and capacity consequences in plain language.
- Distinguish fixed commitments, current-plan blocks, proposed task blocks,
  excluded work, and coarse project-capacity reservations.
- Add explicit whole-plan accept, discard, and single-session restore operations
  with a documented machine-owned Org representation for the current plan.
- Preserve solver proof detail and snapshot freshness behind a compact primary
  status of `FITS`, `AT RISK`, `DOES NOT FIT`, or `NEED INFO`.
- Keep generated schedules read-only until explicit acceptance; stale or
  unverified drafts cannot replace the current plan.

## Capabilities

### New Capabilities

- `adjustable-schedule-drafts`: Candidate generation, bounded manipulation, live
  consequence feedback, explanation, whole-plan replacement, and restore.

### Modified Capabilities

- `portfolio-feasibility-review`: Solver placements may feed an explicitly
  accepted current plan through a guarded whole-plan replacement boundary rather
  than remaining permanently shadow-only.
- `portfolio-review-interaction`: User-facing planning status gains a compact
  summary and navigation into the schedule candidate while retaining detailed proof
  and freshness evidence.
- `lifeos-user-manual`: Scenario and planning guidance gains a draft-review-accept
  workflow and clearly separates proposed from accepted plans.

## Impact

- Emacs schedule workbench, one transient candidate, background analysis,
  bounded manipulation commands, rendering, source navigation, and draft undo.
- Machine-owned Org representation and write transaction for complete current
  plans, including conflict detection and plan-level source validation.
- Solver/scenario request construction and result explanation; protocol changes
  may be required for exact candidate placements and exclusions.
- Existing read-only safety assertions, ERT/Vitest coverage, documentation, and
  migration of any previously manual scheduling convention.
