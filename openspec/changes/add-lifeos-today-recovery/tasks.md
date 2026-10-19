## 1. Today State And Plan Boundaries

- [ ] 1.1 Define immutable Today snapshot, recommendation, alternative, evidence-provenance, daily-override, plan-block, and source-identity data structures.
- [ ] 1.2 Implement snapshot construction from current Org tasks, calendar commitments, active clock state, weekly intentions, inbox findings, and accepted planning evidence.
- [ ] 1.3 Define the plan-adapter contract for reading accepted and proposed blocks, building recovery scenarios, and accepting reviewed plans.
- [ ] 1.4 Implement the built-in adapter with a date-scoped in-memory Today plan and verify that it never writes synthetic Org schedule timestamps.
- [ ] 1.5 Add snapshot invalidation and asynchronous request guards so stale results cannot replace newer evidence or retarget source actions.

## 2. Daily Check-In And Recommendation

- [ ] 2.1 Implement date-scoped check-in capture and reset for remaining usable time, current work mode, and one protected outcome.
- [ ] 2.2 Apply daily overrides to Today and recovery inputs without changing recurring availability, weekly intentions, or task and project metadata.
- [ ] 2.3 Implement the recommendation pipeline for active clocks, current accepted blocks, current solver placements, and deterministic local ranking.
- [ ] 2.4 Generate no more than five fitting alternatives with duration, work-mode, provenance, and concise explanation data.
- [ ] 2.5 Implement specific inbox, commitment-review, capture, and metadata-repair fallbacks for cases where no work recommendation is safe.

## 3. Today Dashboard

- [ ] 3.1 Render one read-only Today dashboard with recommendation, alternatives, fixed and accepted work, intention progress, plan feasibility, and incomplete inbox sections.
- [ ] 3.2 Add dashboard actions for refresh, start or clock, source navigation, explanation, daily capacity check-in, recovery, contextual help, and quit.
- [ ] 3.3 Display current, stale, local-only, running, and unavailable evidence distinctly without presenting heuristic fit as solver proof.
- [ ] 3.4 Preserve useful point and window context across refreshes while keeping source buttons bound to the rendered snapshot.

## 4. Replan From Now

- [ ] 4.1 Implement guided disruption capture for completed or skipped work, overruns, reduced capacity, changed work mode, and urgent arrivals.
- [ ] 4.2 Build recovery scenarios whose horizon starts at the captured current minute, preserves elapsed history, and removes unprotected future proposals.
- [ ] 4.3 Add selection and enforcement of fixed commitments, protected accepted blocks, and one protected outcome, including explicit protected-set conflicts.
- [ ] 4.4 Implement solver-backed recovery and deterministic local-only recovery with bounded fallback when metadata prevents safe regeneration.
- [ ] 4.5 Compute a consequence model that classifies every affected item as stayed, moved, deferred, or no longer fits and includes deadline, capacity, intention, and protection effects.
- [ ] 4.6 Render consequence review before acceptance and block acceptance when review is unseen, protected items conflict, or source evidence has become stale.
- [ ] 4.7 Implement explicit accept and cancel through the built-in adapter, refreshing Today after acceptance and leaving plan and Org state unchanged on cancel.

## 5. Optional Schedule-Draft Integration

- [ ] 5.1 Implement optional provider discovery so Today and recovery load and operate when adjustable schedule drafts are absent.
- [ ] 5.2 Add a schedule-draft adapter that reads accepted blocks as plan context and keeps proposed blocks visibly non-authoritative.
- [ ] 5.3 Delegate reviewed recovery acceptance to the schedule-draft guarded transaction, including freshness and source-conflict checks.
- [ ] 5.4 Run shared plan-adapter conformance tests against the built-in adapter and a schedule-draft test provider.

## 6. Verification

- [ ] 6.1 Add ERT coverage for recommendation ordering, bounded alternatives, work-mode and capacity overrides, protected outcomes, intention progress, and daily rollover.
- [ ] 6.2 Add ERT coverage proving useful local fallbacks for unavailable solver evidence and incomplete nonblocking metadata.
- [ ] 6.3 Add recovery tests for overruns, missed blocks, reduced capacity, changed work mode, urgent arrivals, protected conflicts, and work that no longer fits.
- [ ] 6.4 Add transaction tests proving preview and cancel are read-only, acceptance requires reviewed current evidence, and no implicit policy or historical Org edits occur.
- [ ] 6.5 Add asynchronous tests proving stale solver and source snapshots cannot replace or retarget the current Today display.
- [ ] 6.6 Add integration tests for Today and recovery both without schedule drafts and with proposed and accepted schedule-draft blocks.

## 7. User Guidance

- [ ] 7.1 Add the dashboard-first daily reset workflow with check-in, recommendation, clocking, expected outcomes, and local-only fallback guidance.
- [ ] 7.2 Add the Replan from now workflow covering disruption capture, protection, consequence review, acceptance, cancellation, and blocked-metadata recovery.
- [ ] 7.3 Document ephemeral daily overrides and built-in Today plans separately from durable accepted schedule-draft blocks.
- [ ] 7.4 Update contextual help, command references, and documentation integrity checks for all new Today and recovery actions.
