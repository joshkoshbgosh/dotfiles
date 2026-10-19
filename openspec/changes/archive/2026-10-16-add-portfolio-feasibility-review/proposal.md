## Why

LifeOS can validate executable tasks and prove whole-portfolio feasibility, but it
does not provide a top-down way to discover projects, identify incomplete project
definitions, or understand which projects fit. Large projects also cannot be
represented honestly without prematurely inventing a complete task breakdown.

## What Changes

- Add progressive project definition states so projects can be incomplete,
  coarsely estimated, or fully detailed.
- **BREAKING**: require every `#project` to have a deadline before it can receive
  a positive feasibility result.
- Let a project declare a rough total effort, default work mode, estimate
  confidence, and planning chunk size; represent effort not yet allocated to
  executable tasks as virtual, read-only solver work.
- Distinguish capacity feasibility under a coarse estimate from structural
  feasibility over detailed tasks and dependencies.
- Add a portfolio review that lists explicitly recognized projects, orphan work,
  missing inputs, project margins, and portfolio conflict
  involvement.
- Add project-oriented scenario and negotiation operations for estimates,
  deadlines, scope/defer decisions, and required work windows without writing
  planning decisions to Org.
- Remove the fixed `DOMAIN` task/project property and Domain-budget compatibility
  layer; use the existing selector-based `Intentions` table as the only weekly
  time-allocation model across tasks, projects, virtual work, and calendar roles.
- Preserve the visible heuristic and solver shadow boundary until representative
  real-data review and explicit rollout acceptance.

## Capabilities

### New Capabilities

- `progressive-project-definition`: Project recognition, required metadata,
  coarse effort accounting, virtual work generation, and honest definition and
  proof states.
- `portfolio-feasibility-review`: Top-down project inventory, isolated and
  combined feasibility evidence, drill-down diagnostics, and project-level
  scenario negotiation.
- `selector-only-intentions`: Domain-free task metadata, source-aware selector
  evaluation, and shared intention accounting for solver and heuristic reports.

### Modified Capabilities

None. There are no existing OpenSpec capability specifications in this
repository.

## Impact

- Emacs explicit project inventory, validation, summaries, solver normalization, reports,
  scenario UI, and source navigation.
- TypeScript request/response schemas, solver modeling, verification,
  negotiation, and semantic goldens.
- Org project metadata conventions and documentation.
- Existing `DOMAIN`, `Domain budgets`, Domain report blocks, and the independent
  `org-time-budgets` configuration are intentionally unsupported after migration.
- ERT and Vitest coverage for coarse effort accounting, virtual placements,
  per-project attribution, stale-result handling, and portfolio workflows.
- Solver and review behavior remains read-only; no task, project, deadline, or
  schedule writeback is introduced.
