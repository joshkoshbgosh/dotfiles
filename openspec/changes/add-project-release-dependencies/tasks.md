## 1. Characterization And Protocol Boundary

- [ ] 1.1 Add failing ERT cases for project not-before parsing, empty optional scaffolds, task/project release composition, fixed-start conflicts, and virtual-work inheritance
- [ ] 1.2 Add failing ERT cases for project dependency parsing, target typing, duplicate/self/missing edges, pure cycles, mixed task/project cycles, and nearest-project ownership
- [ ] 1.3 Add failing Vitest cases for strict project release/dependency schemas, reference validation, cycle diagnostics, and deterministic virtual evidence
- [ ] 1.4 Add regression tests exposing project deadline scenario recomputation when task-local and project deadlines coexist
- [ ] 1.5 Add regression tests proving minimum-project-work witness accounting excludes borrowed-project placements

## 2. Project Source Model And Guided Editing

- [ ] 2.1 Extend project records, scaffolding, and definition diagnostics with optional `NOT_BEFORE`, treating an empty scaffold as absent and malformed non-empty input as incomplete
- [ ] 2.2 Extend guided project grooming with plain-language immediate-versus-delayed prompts while preserving existing values and avoiding property-name recall
- [ ] 2.3 Register the `project-depends-on` link type and parse only links in the project heading's direct body
- [ ] 2.4 Implement cycle-safe project dependency add/remove/list navigation commands restricted to explicit project targets
- [ ] 2.5 Build validated direct, reverse, transitive, and mixed ownership dependency graphs with source-linked diagnostics
- [ ] 2.6 Implement terminal and commitment semantics for `DONE`, `CANCELLED`, uncommitted, and incomplete prerequisite projects

## 3. Protocol V3 And Scenario Derivation

- [ ] 3.1 Bump protocol and solver versions and extend project records with not-before and prerequisite project IDs
- [ ] 3.2 Preserve task-local deadline and release inputs separately from project bounds and derive effective constraints after project changes
- [ ] 3.3 Add strict project reference, uniqueness, self-edge, cycle, and source-evidence validation
- [ ] 3.4 Extend project scenarios with absent/set/clear not-before semantics and preserve bounds through virtual-work regeneration
- [ ] 3.5 Strengthen virtual-work validation while retaining mandatory, flexible, task-dependency-free, mutually unordered chunks
- [ ] 3.6 Update Emacs normalization, fixtures, semantic goldens, response validation, and stale-version rejection for protocol v3

## 4. Forecast And Normalization

- [ ] 4.1 Normalize date-only and timed project not-before timestamps using local deadline timezone conventions
- [ ] 4.2 Apply effective project/task release bounds to explicit and virtual work without constraining borrowed prerequisite work by the dependent project's bound
- [ ] 4.3 Extend the visible heuristic to honor project releases and detailed project finish-to-start ordering
- [ ] 4.4 Withhold dependent heuristic placements when prerequisite completion contains unmodeled virtual residual and report an actionable coarse-prerequisite finding
- [ ] 4.5 Recompute effective task deadlines correctly after project deadline scenarios and retain source attribution for both bounds

## 5. Solver Scoping And Constraints

- [ ] 5.1 Add project release constraints for every selected explicit, virtual, and fixed owned task with stable project/task attribution
- [ ] 5.2 Derive aggregate project start/completion expressions and enforce whole-project finish-to-start dependencies without ordering sibling virtual chunks
- [ ] 5.3 Expand isolated project scopes through transitive prerequisite-project demand and then through task prerequisite closure
- [ ] 5.4 Expand portfolio mandatory demand through prerequisite-project closure, including otherwise uncommitted definition-ready prerequisites
- [ ] 5.5 Return `UNKNOWN` for incomplete prerequisite evidence and structural cycles instead of optimistic feasibility or ordinary scheduling infeasibility
- [ ] 5.6 Attribute borrowed prerequisite projects, forced commitment demand, release conflicts, and dependency conflicts in project and portfolio results
- [ ] 5.7 Fix project-specific work-window witness accounting before dependency closure introduces additional borrowed placements

## 6. Negotiation And Independent Verification

- [ ] 6.1 Reimplement latest-safe-project-start as a bounded search over the project not-before field
- [ ] 6.2 Return `UNKNOWN` for latest-start queries targeting incomplete, uncommitted, or unmodeled project demand
- [ ] 6.3 Independently verify task-local releases, project releases, fixed-start contradictions, and virtual placement bounds
- [ ] 6.4 Independently verify prerequisite-project completion, dependent-project start, required predecessor inclusion, and ownership
- [ ] 6.5 Add forged-result mutation tests for release and dependency violations and preserve last-good behavior on verification failure

## 7. Portfolio UI And Red-Green Workflow

- [ ] 7.1 Add not-before, direct prerequisites, dependents, and prerequisite-closure summaries to portfolio rows and drilldowns
- [ ] 7.2 Render source-linked release, wrong-target, cycle, cancelled-prerequisite, incomplete-prerequisite, and coarse-forecast findings
- [ ] 7.3 Show baseline/scenario project release deltas and clarify that latest safe start is a lower-bound negotiation rather than a persisted first placement
- [ ] 7.4 Add ERT rendering and interaction coverage for grooming guidance, dependency navigation, and snapshot-safe source links
- [ ] 7.5 Confirm analysis, forecasting, scenarios, negotiations, and report rendering remain read-only outside explicit grooming/dependency commands

## 8. Documentation And Verification

- [ ] 8.1 Extend `~/Work/lifeos/docs/lifeos/` with project not-before versus fixed scheduling, task versus project release, and date-only timezone semantics
- [ ] 8.2 Extend the existing project diagnostics, standard property completion, settings launcher, and Portfolio Review controls for project release/dependency findings
- [ ] 8.3 Document task dependencies versus whole-project dependencies, coarse prerequisite assurance, terminal states, and forced prerequisite demand in the current user manual
- [ ] 8.4 Update protocol, solver design, current-system, package README, examples, commands, and keybindings for protocol v3
- [ ] 8.5 Run all ERT, TypeScript checking/build, Vitest, semantic goldens, deterministic tests, npm audit, OpenSpec strict validation, and `git diff --check`
- [ ] 8.6 Exercise immediate, future-gated, detailed-dependent, coarse-dependent, incomplete-prerequisite, and cyclic projects on representative real data while confirming Org hashes remain unchanged
