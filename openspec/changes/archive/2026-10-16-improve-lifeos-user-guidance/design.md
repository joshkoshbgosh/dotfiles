## Context

LifeOS currently has two different usability tiers. `#task` headings receive immediate structured diagnostics, local overlays, next/previous navigation, guided grooming, and generic Org completion for enumerated values. `#project` headings are validated while the global project inventory is built, but their definition diagnostics are primarily exposed in the Portfolio Review; their local overlays contain metrics rather than navigable errors, Needs Grooming can classify a project as a malformed task, and generic Org editing lacks project enum completion.

Configuration is also divided among Elisp fallbacks, recurring and weekly Org tables, per-project properties, and non-configurable schema vocabularies without one entry point explaining which layer to edit. The Portfolio Review is rendered in a minimal `special-mode` derivative and does not explain its controls or reliably distinguish fresh, running, stale, and local-only evidence.

The existing LifeOS documentation combines onboarding, workflows, schemas, solver concepts, command inventories, configuration, calendar details, architecture, and verification. This is useful as reference but not as an action-oriented manual. The primary user is easily overwhelmed and distracted, so the first visible material must answer “what do I do now?” and defer theory until requested.

The implemented TODO-state semantics remain unchanged by user decision. The manual must document actual behavior and sharp edges rather than inventing cleaner semantics.

## Goals / Non-Goals

**Goals:**

- Give projects the same red-to-remediation loop users already receive for tasks.
- Use one canonical source for each project diagnostic and allowed-value vocabulary.
- Make configuration destinations discoverable without requiring variable, property, heading, or table-name recall.
- Make Portfolio Review evidence and interaction understandable from the buffer itself.
- Create an Org-native, progressively disclosed manual organized around user goals and examples.
- Clearly separate current behavior, known limitations, proposed behavior, and developer internals.

**Non-Goals:**

- Change TODO-state semantics, solver selection policy, waiting resolution, or scheduling priority.
- Implement project `NOT_BEFORE` or project dependency semantics from `add-project-release-dependencies`.
- Replace Org Customize or existing `planning.org` tables with a new persistence format.
- Make analytical commands write schedules, scenarios, or policy.
- Convert the protocol and solver implementation references into beginner documentation.

## Decisions

### 1. Refactor project validation into a canonical diagnostic path

Project definition validation will be extracted from inventory assembly into reusable functions that accept the same project and descendant-task records. Inventory construction and point-level diagnostics will call those functions rather than maintaining separate rule sets.

Heading-local definition diagnostics will be computed without waiting for solver evidence. Cached forecast and portfolio metrics may still arrive asynchronously and will be appended as a separate summary. This makes missing or invalid metadata responsive while preserving the shared global analysis cache for expensive forecasting.

Alternative considered: display only cached inventory diagnostics. Rejected because the current idle delay recreates the exact lag and invisibility that users experience today.

### 2. One overlay can contain errors and project status, but errors lead

A project heading may need both an actionable diagnostic indicator and useful effort/forecast metrics. The overlay will retain both, with severity counts first and definition/forecast summary second. Its diagnostic text properties will participate in the same next/previous navigation as task diagnostics.

`my/lifeos-explain-at-point` will present project errors with remediation before explanatory metrics. Needs Grooming will create explicitly typed task or project records and will never run task validation against a `#project` heading.

Alternative considered: a second project-only diagnostics mode. Rejected because it would create competing navigation and visual conventions.

### 3. Preserve current project definition semantics

This change improves presentation but does not alter which explicit projects are `INCOMPLETE`, `COARSE`, or `DETAILED`, including current validation of visible uncommitted projects. Any future change to commitment-sensitive validation requires its own semantic proposal.

### 4. Reuse Org's standard allowed-value mechanism

Allowed enum values will be centralized as LifeOS constants and registered through exact `<PROPERTY>_ALL` names in `org-global-properties`. `DEFAULT_WORK_MODE` and `ESTIMATE_CONFIDENCE` will therefore behave like existing `WORK_MODE` and `IMPACT` editing. Grooming, validation, scenarios, and property completion will all consume the same constants.

Duration and timestamp properties remain validated free-form values because presenting a closed completion list would be misleading.

Alternative considered: a custom `org-property-allowed-value-functions` hook. Rejected for the current closed global vocabularies because standard `_ALL` declarations are simpler and match existing behavior.

### 5. Separate configuration layers and expose one launcher

A `my/lifeos` customization group will own LifeOS `defcustom` variables. A single interactive settings command will present user-language destinations:

- LifeOS Emacs preferences;
- recurring planning policy;
- this week's policy override;
- project-specific overrides at point;
- configuration manual.

The command will navigate existing configuration without mutation. If a selected Org section or complete table does not exist, it may offer an explicit confirmed insertion action; cancellation and validation failure leave source unchanged.

The manual will distinguish fixed schema vocabularies from configurable defaults so property completion is not mistaken for policy customization.

Alternative considered: put every setting in Customize. Rejected because weekly and recurring policy are authoritative planning data and belong in Org.

### 6. Treat Portfolio Review as a user-facing report, not a mode name

The Lisp mode symbol remains an implementation detail. The rendered buffer will call itself “Portfolio Review,” explain its purpose and read-only boundary, display evidence freshness, and show a compact control legend.

Its mode map will provide refresh, next/previous project, visit source, groom selected project, help, and quit operations. Refresh will explicitly rebuild project analysis and request solver evidence when shadow solving is enabled. Rendering will preserve useful point/window position when asynchronous evidence arrives.

Freshness states are:

- `RUNNING`: a newer request is in progress;
- `CURRENT`: the accepted result matches the current request and analysis;
- `STALE`: accepted evidence is from an older request or invalidated analysis;
- `LOCAL ONLY`: inventory is available but no accepted solver result exists;
- `UNAVAILABLE`: analysis could not be built, with the failure disclosed.

### 7. Use an Org-native manual with an action-first hub

`~/Work/lifeos/docs/lifeos/index.org` will be the user-manual root. It will ask what the user wants to do and link to small workflow chapters. Every workflow chapter begins with:

1. Do this now.
2. What you should see.
3. A complete example.
4. If it turns red.
5. Why this works.
6. Related reference.

The short `~/Work/lifeos/README.md` will explain the product, installation entry point, current/proposed status, and links to the user and developer documentation. Existing technical Markdown documents in dotfiles remain authoritative deep references initially and are linked from the developer section rather than duplicated.

The manual will state current TODO-state behavior precisely. In particular, it will say that `NEXT` is a guarded human workflow marker rather than solver priority, only a future parseable `WAIT_UNTIL` produces a modeled waiting release, dependency-only or `WAITING_FOR` waiting remains unresolved to the solver, and the visible heuristic currently omits all `WAITING` work.

### 8. Make documentation integrity testable

ERT will verify that commands and keybindings named by the manual exist, local Org file links resolve, project enum vocabularies agree, and generated/help text uses user-facing terms. Examples that represent parsed data will be shared with or mirrored by parser fixtures where practical.

Volatile test counts and audit claims will not be embedded throughout the manual. They belong in a dated verification/status location.

### 9. Keep release/dependency work separate but composable

`add-project-release-dependencies` remains responsible for new planning semantics and protocol v3. When implemented, it will add its project release and dependency guidance to the manual, reuse project diagnostics and completion, and extend Portfolio Review controls rather than creating another documentation hierarchy.

## Risks / Trade-offs

- [Synchronous local project validation becomes slow on very large subtrees] -> Reuse local parsed records, avoid solver/forecast work in the post-command path, and benchmark representative project files.
- [Metrics and local diagnostics briefly describe different snapshots] -> Label forecast evidence separately and refresh it asynchronously after edits.
- [A settings launcher becomes another command to remember] -> Bind and link it from the manual, Portfolio Review help, and relevant diagnostics; preserve ordinary Customize and direct Org editing.
- [Org documentation is less convenient on repository hosting sites] -> Keep a concise Markdown README with direct links and use plain Org constructs that render acceptably outside Emacs.
- [Documenting current WAITING limitations normalizes accidental behavior] -> Mark them explicitly as current limitations and keep state redesign outside this change rather than hiding the mismatch.
- [Documentation and keybindings drift] -> Add integrity tests for command symbols, links, and documented bindings.
- [The manual duplicates technical references] -> Keep workflow explanations intentionally shallow and link to existing architecture/protocol documents for details.

## Migration Plan

1. Add characterization tests for current project diagnostics, state behavior, property completion, configuration precedence, and Portfolio Review freshness.
2. Refactor and expose project diagnostics without changing definition outcomes.
3. Add project overlays, navigation, explain-at-point, grooming-report classification, and post-groom validation.
4. Centralize enum vocabularies and register project allowed values.
5. Add the LifeOS customization group and settings launcher.
6. Upgrade Portfolio Review interaction and freshness display.
7. Create the Org manual under `~/Work/lifeos`, reduce its README, and link retained dotfiles technical references.
8. Add documentation-integrity checks and run the full Emacs and solver verification suites.

Rollback is file-local: the manual and UI affordances can be removed without migrating Org data. No authoritative task, project, calendar, or planning schema changes are introduced.

## Open Questions

- Which leader key should open the settings launcher without conflicting with existing LifeOS bindings?
- Should the first version of the settings launcher only navigate, or also offer confirmed creation of missing recurring and weekly table templates?
- Should historical session transcripts move under an explicitly archival directory, or only be excluded and labeled from active documentation navigation?
