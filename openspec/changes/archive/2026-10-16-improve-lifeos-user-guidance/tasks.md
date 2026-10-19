## 1. Characterize Current Behavior

- [x] 1.1 Add ERT characterization for project definition diagnostics, commitment, effort accounting, and current `INCOMPLETE`/`COARSE`/`DETAILED` outcomes
- [x] 1.2 Add ERT coverage showing current project overlays are non-navigable summaries and Needs Grooming can misclassify projects as tasks
- [x] 1.3 Add ERT characterization for standard Org allowed-value completion on task and project properties
- [x] 1.4 Add ERT characterization for Portfolio Review local-only, accepted, running, and stale evidence inputs
- [x] 1.5 Add behavior fixtures for current `TODO`, `NEXT`, `WAITING`, `SOMEDAY`, `WAIT_UNTIL`, dependency, heuristic, and solver semantics used by the manual

## 2. Canonical Project Diagnostics

- [x] 2.1 Extract reusable project diagnostic construction from project inventory assembly without changing existing definition outcomes
- [x] 2.2 Add point-level project diagnostic lookup that reports heading-local errors without waiting for solver evidence
- [x] 2.3 Render project severity counts before cached definition and forecast summary metrics in Org overlays
- [x] 2.4 Include project diagnostic overlays in next/previous diagnostic navigation while preserving source-order wrapping
- [x] 2.5 Extend explain-at-point to show project findings, remediation, and metrics in that order
- [x] 2.6 Make Needs Grooming build typed project and task records, include explicit projects without TODO states, and avoid task validation on project headings
- [x] 2.7 Make project grooming run canonical validation immediately and report success or actionable remaining findings
- [x] 2.8 Add ERT coverage for local responsiveness, navigation, explanation, grooming classification, read-only refresh, and unchanged valid-project semantics

## 3. Project Property Completion

- [x] 3.1 Centralize estimate-confidence vocabulary and replace duplicated literals in grooming, validation, and scenarios
- [x] 3.2 Register exact standard Org allowed values for `DEFAULT_WORK_MODE` and `ESTIMATE_CONFIDENCE`
- [x] 3.3 Verify task and project grooming, validation, scenarios, and generic Org property editing consume the canonical vocabularies
- [x] 3.4 Add ERT coverage for allowed values and confirm duration/timestamp properties remain validated free-form inputs

## 4. Configuration Guidance

- [x] 4.1 Define a dedicated LifeOS Customize group and assign all LifeOS planning and solver `defcustom` preferences to it
- [x] 4.2 Implement a user-language settings launcher for Emacs preferences, recurring policy, current-week policy, project overrides, and configuration help
- [x] 4.3 Implement read-only navigation to existing recurring, weekly, and project configuration destinations with actionable missing-context messages
- [x] 4.4 Add explicitly confirmed insertion of complete missing policy templates, preserving source on cancellation or validation failure
- [x] 4.5 Link configuration-related diagnostics and reports to the matching settings destination and manual section
- [x] 4.6 Add ERT coverage for configuration destinations, precedence labels, valid templates, cancellation, and no-write paths

## 5. Portfolio Review Interaction

- [x] 5.1 Derive `RUNNING`, `CURRENT`, `STALE`, `LOCAL ONLY`, and `UNAVAILABLE` evidence states from analysis and request context
- [x] 5.2 Add a first-screen purpose, read-only notice, evidence state, row/drilldown explanation, and compact control legend
- [x] 5.3 Add mode commands and bindings for refresh, next/previous project, visit source, groom selected project, contextual help, and quit
- [x] 5.4 Make refresh explicitly rebuild analysis and request solver evidence when shadow solving is enabled
- [x] 5.5 Preserve per-window reading context during asynchronous rerender and retain snapshot-bound source markers
- [x] 5.6 Add ERT rendering and interaction coverage for all evidence states, controls, invalid context, stale source, and point preservation

## 6. Org-Native User Manual

- [x] 6.1 Replace `~/Work/lifeos/README.md` with a concise overview, installation/start link, user-manual link, status distinction, and developer-reference links
- [x] 6.2 Create `~/Work/lifeos/docs/lifeos/index.org` with goal-oriented first-screen paths and clear current/proposed/developer labels
- [x] 6.3 Write Start Here and capture/groom/choose-work workflows using action, expected-result, example, recovery, explanation, and reference sections
- [x] 6.4 Write daily reset, project creation, weekly planning, and scenario/negotiation workflows using the same progressive-disclosure template
- [x] 6.5 Write troubleshooting chapters for red headings, `UNKNOWN`, calendar freshness, configuration errors, and solver failures
- [x] 6.6 Write current state and timing guidance that accurately covers `TODO`, `NEXT`, `WAITING`, `SOMEDAY`, `WAIT_UNTIL`, dependencies, and known planner limitations
- [x] 6.7 Write task-property, project-property, configuration-layer, command, keybinding, and assurance reference chapters
- [x] 6.8 Add a developer manual index that links the retained architecture, solver design, protocol, validation, testing, and change-status material without duplicating it
- [x] 6.9 Mark historical transcripts as non-authoritative and prevent them from appearing in active manual navigation

## 7. Documentation Integrity And Change Integration

- [x] 7.1 Add automated checks for local Org file/heading links and report each broken source location
- [x] 7.2 Add automated checks that documented interactive commands exist and documented leader bindings match configuration
- [x] 7.3 Add automated checks that documented task/project enum values match canonical code vocabularies
- [x] 7.4 Move volatile verification counts and audit claims to one dated status location and remove duplicated claims from workflow documentation
- [x] 7.5 Update `add-project-release-dependencies` documentation tasks to extend this manual, project diagnostics, completion, settings, and Portfolio Review framework

## 8. Verification

- [x] 8.1 Run all LifeOS ERT suites and confirm project diagnostics introduce no task-diagnostic or project-definition regressions
- [x] 8.2 Run TypeScript check, build, Vitest, semantic goldens, deterministic tests, and npm audit
- [x] 8.3 Exercise capture, incomplete task, incomplete project, project grooming, settings navigation, Portfolio Review refresh, stale evidence, and manual recovery paths on representative data
- [x] 8.4 Confirm analytical paths preserve authoritative Org hashes and only explicit confirmed grooming or configuration commands write source
- [x] 8.5 Run OpenSpec strict validation, documentation-integrity checks, and `git diff --check`
