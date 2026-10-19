# LifeOS Active Handoff

This is the active handoff for review and rollout. Autonomous implementation is
complete. Current behavior is documented in
[`docs/lifeos-current-system.md`](docs/lifeos-current-system.md), the design in
[`docs/lifeos-solver-design.md`](docs/lifeos-solver-design.md), and the wire
contract in [`docs/lifeos-solver-protocol.md`](docs/lifeos-solver-protocol.md).

## Objective

Evaluate the solver-backed weekly planner and guarded schedule-candidate workflow
on real LifeOS data while retaining the visible heuristic as fallback. Planning
writes occur only through explicit complete candidate acceptance or bounded
restore.

## Safety Boundary

- Org files under `~/Work/lifeos/` remain authoritative and must not be edited
  by repository automation.
- Solver normalization, scenarios, negotiation, reports, and comparisons are
  read-only. They never create timestamps or change tasks, intentions,
  availability, configuration, commitments, or calendar data.
- The deterministic heuristic remains visible and continues to drive existing
  overlays and selector-based intention dynamic blocks.
- Solver output remains shadow evidence until the user opens, reviews, and
  explicitly accepts a complete current candidate.
- Candidate acceptance and restore may replace only the machine-owned
  `Accepted schedule` subtree after guarded preflight.

## Implementation Status

All planned autonomous implementation is complete:

- TypeScript/Z3 feasibility, safety, reserve, sleep, travel, release-time,
  intention optimization, stress classification, and deterministic placement;
- all five discriminated negotiation queries: deadline-only maximum, safe
  maximum, minimum required work in a window, latest safe discretionary start,
  and minimal commitment unlock set;
- recognized/probable/orphan project inventory, progressive project definitions,
  deterministic virtual effort, isolated proofs, portfolio proofs, and the
  read-only portfolio review;
- all five project negotiations: maximum effort, minimum work in a window,
  latest safe start, earliest feasible deadline, and minimal project defer set;
- strict request, reference, scenario, stress-profile, and query validation;
- normalized `WAIT_UNTIL`, calendar freshness, attendance, travel evidence,
  per-project safety buffers, calendar roles, and source-aware Intentions;
- asynchronous stale-safe Emacs integration and last-good-result retention;
- structured baseline/scenario report, raw JSON view, source links,
  heuristic/solver discrepancy view, margins, relaxations, and comparison
  deltas;
- composable ephemeral task, intention, and project scenario UI plus
  baseline/scenario negotiation UI;
- recurring and weekly whole-table solver configuration;
- generated estimate-overrun, lost-Deep-window, and unexpected-appointment
  stress profiles;
- independent returned-model verification and bounded UNSAT-core shrinking;
- one revision-safe schedule candidate with exact placement, exclusion,
  draft-only estimates, undo, compact consequence review, guarded complete-plan
  acceptance, and bounded single-session restore;
- SAT/UNSAT semantic goldens, property tests, deterministic tests, and CI for
  ERT, TypeScript checking, build, Vitest, and npm audit.

Verified baseline:

- **158/158 ERT** plus **8/8 documentation ERT**;
- **51/51 Vitest**;
- TypeScript check and build pass;
- npm audit reports zero vulnerabilities at moderate-or-higher severity.

There is no remaining autonomous implementation claim in this handoff.

## Real-Data Shadow Check

The latest real-data shadow exercise over `~/Work/lifeos/` on 2026-10-17 returned
a schema-valid solver result and confirmed SHA-256 hashes of all authoritative Org
files were unchanged. Complete replacement and restore were exercised only
against disposable `planning.org` copies. The earlier 2026-10-15 portfolio review
found:

- 1 explicitly recognized project and 0 orphan executable tasks; untagged
  headings are intentionally ignored rather than inferred as projects;
- the recognized project is `INCOMPLETE` because its total project effort is
  unspecified and active descendants remain unresolved;
- baseline portfolio feasibility is correctly `UNKNOWN` with modeled-subset
  disclosure rather than a false green result;
- an ephemeral project-assumption scenario produced one project delta, and a
  project-effort negotiation returned structured evidence while preserving the
  unknown status of incomplete source data;
- SHA-256 hashes of every authoritative Org file were unchanged after baseline,
  isolated, scenario, negotiation, and report rendering.

## Provisional Review Values

The code contains conservative fallback choices so an absent Org table remains
modelable. These are implementation defaults, not personally approved policy:

| Policy | Chosen code fallback |
|---|---|
| Sleep envelope | `22:00` to `09:00` |
| Sleep minimum | `8:00` |
| Default deadline safety buffer | `24:00` |
| Daily reserve | `1:00` |
| Weekly reserve | `4:00` |
| Minimum reserve block | `1:00` |
| Known in-person travel | `0:45` before and after |
| Unknown-location travel | `1:00` before and after |
| Remote setup | `0:15` before |
| Calendar import lookahead | `60 days` |
| Stress profiles | disabled unless explicitly configured |

The complete example in [`README.md`](README.md) is a provisional review
configuration. Its enabled `25%` estimate overrun, lost largest Deep window,
and `1:00` unexpected appointment are proposed review values, not user approval.

## Remaining User Actions

1. Review and approve or change every solver policy value, then add a complete
   recurring `Solver configuration` table to `planning.org`; use a complete
   weekly table only when replacing the recurring policy for that week.
2. Add or review selector-based weekly `Intentions`. With no weekly or recurring
   table, work remains schedulable but no allocation targets are configured.
3. Run a successful calendar fetch or `my/org-gcal-full-refresh`, confirm its
   coverage reaches the assurance horizon, and verify deleted recurring events
   disappear.
4. Use `my/lifeos-solver-show-portfolio-review` (`M-; n p P`), the solver
   report, discrepancies, project scenarios, and all five project negotiations
   during a representative week. Inspect incomplete projects, orphan
   work, coarse assumptions, cross-project conflicts, every `UNKNOWN`, and the
   modeled-subset disclosure.
5. Open schedule candidates only from current Portfolio Review evidence. Review
   the complete candidate and its write scope before accepting; keep using the
   heuristic whenever candidate evidence is unavailable or unsuitable.
6. Configure Beorg manually to retain `calendar.org` while hiding its duplicate
   direct iOS calendar:

   ```scheme
   (set! org-overdue-includes-scheduled #f)
   (set! agenda-include-calendar #f)
   (set! tasks-include-calendar #f)
   ```

7. Change completion-relative daily routines from `+1d` to `.+1d` where that
   behavior is desired.
8. Continue gradual task and explicit project grooming without inventing
   uncertain estimates or dates.
9. Rerun the verification commands in [`README.md`](README.md), including npm
   audit, before rollout.
