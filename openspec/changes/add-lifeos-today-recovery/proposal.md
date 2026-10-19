## Why

LifeOS has reports for planning and troubleshooting but no single daily surface
for deciding what to do now, and no first-class workflow for recovering after a
day diverges from the plan. Recovery currently demands model repair and report
interpretation at the moment the user has the least executive capacity.

## What Changes

- Add a single LifeOS Today dashboard showing one recommended action, a small set
  of fitting alternatives, fixed and accepted work for today, weekly intention
  progress, plan feasibility, and incomplete inbox items.
- Add a lightweight daily check-in for remaining usable time, current work mode,
  and one protected outcome without requiring a weekly-policy rewrite.
- Add `Replan from now`, which records what happened, preserves fixed and
  explicitly protected commitments, discards obsolete proposed placements, and
  rebuilds the remainder from the current time.
- Clearly summarize what stayed, moved, was deferred, or no longer fits before the
  revised plan is accepted.
- Keep metadata repair secondary unless missing information prevents a safe next
  recommendation; always provide a useful fallback when proof is unavailable.
- Add direct actions for starting or clocking the recommendation, visiting its
  source, explaining it, changing today's capacity, and entering recovery.
- Update daily-reset and troubleshooting guidance around attention recovery
  rather than configuration repair.

## Capabilities

### New Capabilities

- `lifeos-today-dashboard`: A single daily decision surface with a recommended
  action, alternatives, plan context, intention progress, and contextual actions.
- `replan-from-now`: Guided disruption capture, protected-commitment selection,
  future-plan regeneration, consequence review, and explicit acceptance.

### Modified Capabilities

- `lifeos-user-manual`: Daily reset and failure recovery become dashboard-first,
  with troubleshooting details deferred until they block useful action.

## Impact

- Emacs Today dashboard, daily override/check-in state, recommendation logic,
  clock integration, source navigation, and recovery workflow.
- Integration with accepted schedule drafts when available; the dashboard must
  still provide useful actions before the schedule-draft change is implemented.
- Solver and heuristic refresh triggers from the current minute, plus plain-
  language consequence summaries and stale-evidence handling.
- ERT and integration tests for overruns, missed blocks, reduced capacity,
  changed work mode, urgent arrivals, infeasibility, and unavailable solver
  evidence.
