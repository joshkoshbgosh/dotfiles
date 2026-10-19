## 1. Project Inventory And Definition

- [x] 1.1 Add failing ERT cases for explicit projects, ignored untagged headings, orphan tasks, and active versus uncommitted project states
- [x] 1.2 Implement canonical project inventory records with stable source markers and commitment classification
- [x] 1.3 Add failing ERT cases for required project ID, deadline, `PROJECT_EFFORT`, and coarse metadata validation
- [x] 1.4 Implement project diagnostics and `INCOMPLETE`, `COARSE`, and `DETAILED` definition states
- [x] 1.5 Add failing ERT cases for effort-envelope allocation, completed tasks, over-allocation, and unresolved descendant work
- [x] 1.6 Implement explicit, remaining, and unallocated project effort accounting in the shared analysis snapshot

## 2. Virtual Coarse Work

- [x] 2.1 Add failing ERT normalization cases for deterministic chunk IDs, chunk remainders, inherited metadata, and project evidence
- [x] 2.2 Generate virtual project work from positive unallocated effort without creating Org headings or markers
- [x] 2.3 Extend request schemas and strict validation with virtual-work and project-definition evidence
- [x] 2.4 Add Vitest protocol tests that reject malformed coarse metadata and preserve deterministic normalized requests
- [x] 2.5 Extend independent model verification to validate virtual chunks with the same physical constraints as explicit tasks

## 3. Structured Project Attribution

- [x] 3.1 Add failing schema and golden tests for project IDs on margins and multi-task, multi-project, and shared conflict attribution
- [x] 3.2 Extend solver constraint records and result schemas with structured task and project ownership
- [x] 3.3 Preserve all honest ownership for pairwise, deadline, reserve, calendar, travel, and preflight conflicts
- [x] 3.4 Update Emacs response validation and source-link mapping for project-owned and shared evidence

## 4. Isolated And Portfolio Proofs

- [x] 4.1 Add failing Vitest cases for isolated project scope, unrelated flexible work exclusion, fixed commitments, and cross-project prerequisite closure
- [x] 4.2 Implement deterministic isolated project solve scopes with bounded timeouts and per-project feasibility, safety, margins, and borrowed prerequisites
- [x] 4.3 Add failing cases where projects fit alone but fail together and where incomplete committed projects prevent portfolio green
- [x] 4.4 Implement portfolio project results and modeled-subset disclosure on the existing global solve
- [x] 4.5 Extend returned-model verification and semantic goldens for isolated and portfolio project results
- [x] 4.6 Preserve request-ID cancellation, last-good retention, and stale-result rejection across the expanded asynchronous response

## 5. Portfolio Review UI

- [x] 5.1 Add failing ERT rendering cases for separate definition, isolated, and portfolio statuses; effort columns; margins; confidence; and next findings
- [x] 5.2 Implement the read-only portfolio review with explicit project rows and orphan work
- [x] 5.3 Add project drill-down sections for metadata errors, explicit and virtual work, borrowed prerequisites, conflicts, and assumptions
- [x] 5.4 Add snapshot-safe source buttons for projects, tasks, and orphan work
- [x] 5.5 Add discoverable commands and leader bindings for portfolio review and guided project grooming without replacing existing reports or overlays

## 6. Project Scenarios

- [x] 6.1 Add failing ERT and Vitest cases for composable project effort, deadline, commitment, work-mode, chunk-size, and confidence changes
- [x] 6.2 Extend scenario schemas and application so project deltas apply before effective deadlines and virtual work are derived
- [x] 6.3 Add interactive scenario actions for changing project assumptions and deferring a project without Org writeback
- [x] 6.4 Render baseline-versus-scenario project status, effort, margin, conflict, and portfolio deltas

## 7. Project Negotiation

- [x] 7.1 Add failing semantic tests for maximum project effort and minimum required project work in a window
- [x] 7.2 Implement aligned bounded project-effort and required-work queries for deadline-only and safe assurance
- [x] 7.3 Add failing semantic tests for latest safe project start and earliest feasible project deadline
- [x] 7.4 Implement project start and deadline boundary searches with explicit horizon and unknown outcomes
- [x] 7.5 Add failing tests for deterministic cardinality-minimal project defer sets
- [x] 7.6 Implement candidate-bounded minimal defer negotiation and conflict-involvement reporting
- [x] 7.7 Add interactive project query prompts and render baseline/scenario negotiation answers in the portfolio review

## 8. Documentation And Verification

- [x] 8.1 Document project metadata, effort-envelope semantics, definition states, proof language, scenarios, and queries in the README and current-system guide
- [x] 8.2 Add a complete coarse-to-detailed Org example demonstrating that explicit tasks replace rather than add to virtual work
- [x] 8.3 Run all ERT, TypeScript checking, build, Vitest, semantic goldens, deterministic tests, and npm audit
- [x] 8.4 Exercise the portfolio review on real LifeOS data and record expected handling of explicit incomplete projects, orphan work, coarse estimates, and cross-project conflicts
- [x] 8.5 Confirm Org files are unchanged by baseline, isolated, scenario, and negotiation runs before retaining the feature in shadow mode

## 9. Selector-Only Intentions

- [x] 9.1 Add failing ERT cases proving tasks need no fixed classification and remove Domain validation, scaffolding, grooming, inheritance, and record fields
- [x] 9.2 Move restricted selector parsing/evaluation into shared planning analysis and reject the former domain selector
- [x] 9.3 Replace Domain budget parsing and reports with selected Intentions accounting for remaining, clocked, fixed, proposed, and overlapping work
- [x] 9.4 Remove Domain fields from forecast placements and render matching intention names and weekly intention pressure
- [x] 9.5 Remove solver Domain exceptions and compatibility fallbacks; include explicit and virtual work in source-aware intention matches
- [x] 9.6 Replace org-gcal Domain mapping with canonical `CALENDAR_ROLE` mapping and test timed versus all-day accounting
- [x] 9.7 Remove the independent fixed-category `org-time-budgets` module and active configuration
- [x] 9.8 Update active documentation and examples to use selector-only Intentions and protocol v2 terminology
- [x] 9.9 Verify no LifeOS Domain schema, selector, budget parser, report, fallback, or generated compatibility identifier remains in the repository implementation
