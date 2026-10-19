## 1. Candidate Model and Current-Plan Input

- [x] 1.1 Add failing Emacs tests for `EDITING`, `CHECKING`, `CURRENT`, and `STALE` transitions, monotonic revisions, one-active-candidate enforcement, closing on accept or discard, and current-evidence acceptance eligibility.
- [x] 1.2 Implement the transient candidate document, captured plan-level input fingerprint, revisioned edit history, replacement horizon, lifecycle guards, and one-active-candidate boundary.
- [x] 1.3 Add failing parser tests for absent, valid, malformed, duplicated, contradictory, manually changed, and timestamp-mismatched machine-owned `Accepted schedule` plans.
- [x] 1.4 Implement canonical plan-level metadata and `TASK` and `PROJECT_CAPACITY` child parsing, validation, deterministic ordering, and subtree fingerprints from `planning.org`.
- [x] 1.5 Include a valid current plan as attributable occupied flexible context in ordinary analysis, while replacement-candidate generation converts its replaceable future blocks into source-attributed seed placements and keeps timed `SCHEDULED` work fixed.

## 2. Candidate Edits and Solver Protocol

- [x] 2.1 Add failing Emacs and TypeScript tests for exact placement, exclusion, draft-only re-estimation, and latest-edit undo.
- [x] 2.2 Implement reversible candidate edits for exact placement, exclusion, re-estimation, and undo without source or current-plan writes.
- [x] 2.3 Extend the strict request schema only as needed for candidate ID, revision, captured input fingerprint, normalized request ID, exact placement constraints, exclusions, and estimate overrides, updating fixtures and protocol versions together.
- [x] 2.4 Implement solver handling for exact candidate placements, excluded demand, estimate overrides, current-plan seed stability, and coarse project reservations without task splitting or soft adjustment of explicit user placements.
- [x] 2.5 Return stable task and project attribution, placement and omission rationale, and deadline, safety, intention, estimate-confidence, and capacity evidence needed by the workbench.
- [x] 2.6 Extend independent verification to check candidate edits, current-plan seed conversion, source attribution, planning evidence, and response identity before evidence can become current.

## 3. Live Feasibility and Status

- [x] 3.1 Add deterministic tests for debounce coalescing, immediate local rendering, concurrent requests, out-of-order responses, malformed responses, and authoritative-input invalidation.
- [x] 3.2 Implement the configurable idle debounce and exact candidate-ID, revision, input-fingerprint, request-ID, and verification gates for applying asynchronous results.
- [x] 3.3 Add table-driven tests for `NEED INFO`, `DOES NOT FIT`, `AT RISK`, and `FITS` precedence across freshness, proof, safety, reserve, intention, confidence, and capacity evidence.
- [x] 3.4 Implement the plain-status projection, disable acceptance for `NEED INFO` and `DOES NOT FIT`, require explicit warning confirmation for `AT RISK`, and retain prior evidence only as labeled context.

## 4. Schedule Workbench

- [x] 4.1 Add rendering tests for the header and ordered Schedule, Omissions, and Consequences sections; day grouping; evidence freshness; and textual `[FIXED]`, `[KEEP]`, `[NEW]`, `[MOVED: USER]`, `[MOVED: PLAN]`, `[CAP]`, `[EXCL]`, and `[OMIT]` labels.
- [x] 4.2 Implement a dedicated read-only `special-mode` workbench that renders one candidate rather than side-by-side plans, shows prior intervals only for changed blocks, and includes complete kept, moved, added, removed, excluded, and omitted deltas.
- [x] 4.3 Add selectable block text properties and tests for wrapping `n`/`p` navigation, `RET` details, `v` snapshot-bound source navigation, task and coarse-capacity drilldowns, and actionable invalid-selection errors.
- [x] 4.4 Implement `m` exact-place prompting for date and aligned start with derived end and confirmation, `x` informed exclusion confirmation, `e` source-versus-candidate estimate prompting, and `u` latest candidate-edit undo.
- [x] 4.5 Add asynchronous rendering tests and implementation that mark affected work as checking, show prior proof only as context, disable acceptance, preserve logical selection and window start across updates, and fall back to the nearest surviving selectable block.
- [x] 4.6 Implement `r` stale regeneration with a lost-edit summary and confirmation rather than automatic replay, `d` confirmed discard, `h` contextual help, and `q` window quit without acceptance.
- [x] 4.7 Add `a` acceptance-review entry and `R` bounded previous-plan restore entry with state-sensitive messages; keep authoritative writes behind the acceptance service rather than workbench commands.
- [x] 4.8 Add the Portfolio Review plain-status summary and `s` key to its mode map, control summary, and help for opening the one active candidate from the displayed snapshot, refusing or refreshing stale review evidence.

## 5. Guarded Whole-Plan Replacement

- [x] 5.1 Add transaction tests for complete `FITS` acceptance, warned `AT RISK` acceptance, refused `NEED INFO` and `DOES NOT FIT` acceptance, task and coarse-capacity records, deterministic serialization, dirty target buffers, stale source fingerprints, current-plan changes, fixed conflicts, intersecting boundary blocks, and injected save failures.
- [x] 5.2 Implement a single acceptance API that reparses authoritative input and preflights candidate revision, request identity, plan-level source fingerprint, current-plan subtree, block structure, replacement horizon, fixed conflicts, and target-buffer conditions.
- [x] 5.3 Choose the initial replacement boundary at the first aligned time outside an in-progress accepted block, render the adjustment, preserve records ending at or before it, and reject a newly intersecting block at preflight.
- [x] 5.4 Serialize one canonical machine-owned plan, replace all records after the boundary with the complete candidate including unchanged carried work, and commit through one atomic clean-buffer edit and successful `planning.org` save.
- [x] 5.5 Add acceptance-review rendering and tests for boundary, evidence freshness, specific risk failures, material consequences, complete delta counts, write-scope explanation, normal `FITS` confirmation, second `AT RISK` confirmation, and absent write action for `NEED INFO` or `DOES NOT FIT`.
- [x] 5.6 Close the accepted candidate, refresh current-plan input, invalidate prior evidence, report accepted block count and acceptance time, and reject any attempt to reuse the closed candidate.
- [x] 5.7 Retain at most one in-memory restore token containing exact prior and resulting accepted-subtree text and fingerprints for the latest acceptance in the current Emacs session.
- [x] 5.8 Implement conditional previous-plan restore through the same guarded boundary, refusing restart, intervening acceptance, or changed-subtree cases and regenerating evidence after success.
- [x] 5.9 Add write-spy regression tests proving portfolio review, proofs, scenarios, negotiation, candidate generation, candidate manipulation, quit, discard, failed acceptance, and stale acceptance remain byte-for-byte read-only.

## 6. Documentation and Verification

- [x] 6.1 Add an action-first manual chapter for labels and change provenance, candidate review, exact placement, exclusion, draft-only re-estimation, consequence status, complete acceptance, discard, candidate undo, previous-plan restore, and stale or conflict recovery.
- [x] 6.2 Document the machine-owned current-plan subtree, complete future replacement semantics, fixed-versus-flexible distinction, coarse reservation limits, plain-status mapping, replacement boundary, and guarded write boundary.
- [x] 6.3 Extend documentation integrity tests for new commands, keybindings, candidate-condition and planning-status enums, local links, and current-plan vocabulary.
- [x] 6.4 Run focused ERT and Vitest suites, protocol fixture validation, write-boundary regression tests, and complete LifeOS test suites; fix all failures.
- [x] 6.5 Run a real-data shadow exercise with acceptance disabled and verify Org hashes remain unchanged, then exercise complete replacement and restore only against disposable copies of authoritative files.
