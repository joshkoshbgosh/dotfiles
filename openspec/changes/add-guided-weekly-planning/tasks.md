## 1. Policy Semantics and Characterization

- [ ] 1.1 Add failing ERT cases for recurring availability expansion, per-mode `Add` and `Remove` overlays, add-wins overlap, interval canonicalization, cross-midnight splitting, and unique physical capacity.
- [ ] 1.2 Add failing parser cases for the canonical `Availability exceptions` table, including headers, operations, week-bounded dates, non-empty intervals, canonical modes, and source-linked invalid rows.
- [ ] 1.3 Add failing tests for optional intention bounds, explicit zero, pairwise ordering, minimum shortfall, target deviation, maximum excess, and mandatory work crossing soft bounds.
- [ ] 1.4 Add failing accounting tests for clipped timed-calendar credit, excluded all-day/travel/setup time, overlapping selectors, independent row credit, and single physical-capacity consumption.
- [ ] 1.5 Characterize existing complete weekly intention and Solver configuration replacement behavior so availability overlays do not accidentally change unrelated precedence.

## 2. Availability Exceptions and Effective Policy

- [ ] 2.1 Implement parsing and source diagnostics for canonical weekly `Availability exceptions` tables without creating a second persisted policy format.
- [ ] 2.2 Implement deterministic recurring-window expansion, remove-union subtraction, add-union composition, add-wins conflicts, and adjacent/overlap canonicalization per date and mode.
- [ ] 2.3 Split guided cross-midnight input into canonical dated rows and reject raw rows that cross midnight or leave the selected week.
- [ ] 2.4 Extend effective-policy provenance to distinguish recurring availability, existing exceptions, draft edits, complete weekly intention replacements, Solver configuration replacements, and project overrides.
- [ ] 2.5 Add an explicit migration command that previews conversion of a complete weekly `Availability` replacement into equivalent recurring policy plus exceptions and writes only after confirmation.

## 3. Intention Semantics and Selector Builder

- [ ] 3.1 Implement shared validation and normalization for optional minimum, target, and maximum durations with ordered soft-bound semantics.
- [ ] 3.2 Update heuristic and solver intention objectives to minimize minimum shortfall and maximum excess before target deviation while keeping all intention bounds soft.
- [ ] 3.3 Implement the typed selector-builder model for task tags, project tags, project IDs, task/project properties, work modes, calendar roles, task source, and nested all/any/not groups.
- [ ] 3.4 Populate selector choices from canonical inventories, render plain-language and canonical forms, and preview matching explicit tasks, virtual work, and eligible calendar events.
- [ ] 3.5 Reject empty and unsupported selector forms while retaining valid no-current-match selectors with an immediate warning.
- [ ] 3.6 Add round-trip tests proving guided selectors and raw selector expressions use the same canonical parser, evaluator, calendar-credit rules, and overlap accounting.

## 4. Guided Weekly Draft

- [ ] 4.1 Implement an in-memory weekly draft that snapshots the selected week, source text and hashes, calendar commitments, recurring policy, matching weekly policy, and current analysis identity.
- [ ] 4.2 Implement user-language steps for week selection, calendar review, availability additions/removals, outcome selection, intention bounds, selector construction, and final review without requiring Org syntax.
- [ ] 4.3 Render recurring, existing weekly, draft, and effective values together with exact overlay/replacement precedence and canonical write destinations.
- [ ] 4.4 Preserve inherited intentions without writing a weekly table when unchanged, and materialize the complete effective intention set when any intention is edited.
- [ ] 4.5 Add cancellation and interruption tests proving no Org or calendar source changes before explicit confirmation.

## 5. Immediate Feedback and Solver Evidence

- [ ] 5.1 Recompute validation, effective availability, blocked time, unique and per-mode usable capacity, intention gaps/overlaps, and deterministic heuristic pressure synchronously after every draft edit.
- [ ] 5.2 Label per-mode capacity as overlapping views and prevent UI totals from summing modes or intention rows as physical demand or progress.
- [ ] 5.3 Add debounced solver submission keyed to the exact weekly draft identity and reject every stale, out-of-order, malformed, or independently unverified response.
- [ ] 5.4 Render `RUNNING`, `CURRENT`, `STALE`, `LOCAL ONLY`, and `UNAVAILABLE` evidence separately from immediate capacity arithmetic and heuristic output.
- [ ] 5.5 Add integration tests for rapid edits, source changes during analysis, solver timeout/unavailability, and stale response arrival.

## 6. Confirmed Write Boundary and Settings

- [ ] 6.1 Implement preflight checks for unchanged Org and calendar inputs, fully valid draft state, canonical serialization, parser round-trip, and destination disclosure.
- [ ] 6.2 Apply confirmed weekly policy through one Org buffer transaction and leave authoritative source byte-for-byte unchanged on cancellation, stale input, validation failure, serialization failure, or save failure.
- [ ] 6.3 Add transaction tests for creating a missing week, writing only availability exceptions, writing a complete weekly intention replacement, preserving inherited Solver configuration, and avoiding unrelated policy rewrites.
- [ ] 6.4 Route guided weekly planning through the LifeOS settings entry point and retain a distinct advanced action for visiting canonical raw weekly policy.
- [ ] 6.5 Add keyboard help, source navigation, actionable invalid-state messages, and stable draft context during asynchronous updates.

## 7. Documentation and Verification

- [ ] 7.1 Replace raw-table-first weekly guidance with an action-first guided workflow covering calendar review, exceptions, outcomes, bounds, feedback, preview, confirmation, and cancellation.
- [ ] 7.2 Document availability overlay precedence, complete intention and Solver configuration replacement, intention soft-bound semantics, eligible calendar credit, and non-additive overlaps.
- [ ] 7.3 Retain advanced reference for canonical headings, table schemas, selector expressions, parser rules, migration, and direct Org recovery.
- [ ] 7.4 Extend documentation-integrity checks for the guided command, settings action, exception schema, canonical operations, status vocabulary, and raw-policy links.
- [ ] 7.5 Run focused and complete ERT suites, solver type checking/build/tests, semantic and round-trip fixtures, OpenSpec strict validation, and `git diff --check`.
- [ ] 7.6 Exercise ordinary, reduced-capacity, added-evening, cross-midnight, overlapping-mode, overlapping-intention, stale-source, and solver-unavailable weeks against representative data while confirming no writes occur before acceptance.
