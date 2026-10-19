## Why

LifeOS exposes substantial planning behavior but teaches it through feature and implementation reference, forcing users to understand the data model before they can complete ordinary workflows. Project diagnostics, configuration, property completion, and the portfolio review also lack the immediate guidance already available for tasks, making incomplete work difficult to recognize and repair.

## What Changes

- Give explicit `#project` headings local, navigable, actionable diagnostics comparable to `#task` headings.
- Make Needs Grooming and explain-at-point distinguish project definition errors from task errors and direct users to the correct repair flow.
- Provide valid-value completion for enumerated project properties from one canonical vocabulary source.
- Establish a dedicated LifeOS customization group and one guided settings entry point that distinguishes implementation preferences, recurring policy, weekly overrides, per-project overrides, and fixed schema values.
- Make the Portfolio Review buffer self-describing, freshness-aware, and operable through visible navigation, refresh, grooming, source, help, and quit controls.
- Replace the root feature catalogue with a concise entry point to a nested, Org-native user manual organized around user goals, examples, expected outcomes, and recovery paths.
- Document the current `TODO`, `NEXT`, `WAITING`, `SOMEDAY`, `WAIT_UNTIL`, and dependency behavior honestly, including current planner limitations, without changing state semantics in this change.
- Mark current, proposed, developer, and historical material clearly so proposed behavior is not mistaken for implemented behavior.

## Capabilities

### New Capabilities

- `project-guidance`: Local project validation, remediation, diagnostic navigation, grooming integration, and enumerated property completion.
- `lifeos-configuration-guidance`: A discoverable settings entry point and explicit configuration-layer model.
- `portfolio-review-interaction`: A self-describing, freshness-aware, keyboard-operable Portfolio Review experience.
- `lifeos-user-manual`: An Org-native, progressively disclosed manual organized around user workflows and current behavior.

### Modified Capabilities

None. There are no archived baseline capability specifications; this change builds new operability contracts around the implemented system without changing its planning semantics.

## Impact

- Emacs planning diagnostics, grooming reports, Org property completion, and project analysis in `lifeos-planning.el`.
- Solver report presentation and review-buffer interaction in `lifeos-solver.el`.
- LifeOS customization variables and leader-command discoverability.
- LifeOS `~/Work/lifeos/README.md` and `~/Work/lifeos/docs/lifeos/` Org manual hierarchy; retained developer references remain in dotfiles.
- ERT coverage for project diagnostics, property completion, settings navigation, report interaction, and documentation integrity.
- `add-project-release-dependencies` remains a separate semantic change and will extend this manual and diagnostic framework when implemented.
