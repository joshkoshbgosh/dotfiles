## Context

LifeOS currently discovers textual `#project` headings and associates executable
leaf `#task` records with their nearest project. The heuristic cache provides
project progress, coverage, unplaced counts, and deadline tightness, while the
TypeScript/Z3 solver returns one global feasibility result with per-task margins.
There is no project readiness contract, independent project proof, or portfolio
workbench. Only projects with IDs reach the solver, and undated or unbroken work
can disappear from meaningful assurance.

The change crosses Org metadata, Emacs normalization and UI, the JSON protocol,
Z3 solve orchestration, model verification, and tests. Org remains authoritative;
all generated coarse work, placements, scenarios, and negotiations remain
ephemeral.

## Goals / Non-Goals

**Goals:**

- Make portfolio review the top-down entry point for planning.
- Require a deadline and explicit effort accounting for active projects.
- Account for large, uncertain projects before detailed decomposition.
- Keep definition quality distinct from isolated and combined feasibility.
- Provide trustworthy source attribution and stale-safe asynchronous results.
- Support red-green iteration through project-level scenarios and negotiation.

**Non-Goals:**

- Writing solver placements, deadlines, estimates, or commitment decisions to Org.
- Inferring projects from deadlines, hierarchy, or descendant work, or moving
  orphan tasks.
- Claiming that a coarse capacity model proves unknown sequencing or dependencies.
- Replacing the visible heuristic during this change.
- Automatically deriving rough estimates from project prose or historical data.
- Modeling continuous areas of responsibility as projects; recurring investment
  remains an intention.

## Decisions

### Use one total project effort envelope

`PROJECT_EFFORT` means expected total project effort, including detailed tasks and
work not yet decomposed. Unallocated effort is:

```text
max(PROJECT_EFFORT - sum(EFFORT of all executable descendant tasks), 0)
```

Completed executable tasks remain in the allocation sum so their estimated work
does not reappear. Active explicit tasks retain the existing direct-clock balance
semantics. If explicit task effort exceeds the envelope, explicit work is never
dropped; the project estimate becomes an incomplete-definition diagnostic.

Alternatives considered:

- A manually maintained `UNPLANNED_EFFORT` duplicates bookkeeping and can easily
  double-count detailed tasks.
- Summing only active task effort makes completed work reappear in the residual.
- Requiring full decomposition preserves precision but defeats progressive
  planning and encourages fabricated tasks.

### Generate virtual chunks at normalization time

Positive unallocated effort becomes deterministic synthetic task records using
`PLANNING_CHUNK`, with a smaller final chunk. They inherit the project deadline,
default work mode, project ID, mandatory status, confidence, and project evidence.
IDs use a stable project-derived namespace and ordinal. They are included in
normal model verification but never receive Org markers or writeback behavior.

This reuses the existing interval solver and verifier. A divisible-work Z3 model
would represent coarse capacity more directly, but would introduce a second
placement model throughout optimization, reports, scenarios, and verification.
Chunking is understandable and lets the user state the fragmentation assumption.

### Require coarse metadata rather than hidden planning policy

An active project needs ID, deadline, and `PROJECT_EFFORT`. Positive residual
also requires `DEFAULT_WORK_MODE`, `PLANNING_CHUNK`, and `ESTIMATE_CONFIDENCE`.
There is no undisclosed default chunk or confidence. Project and task
classification is expressed only through ordinary tags/properties referenced by
selectors; no fixed classification property is required.

Only an explicit `#project` tag establishes project identity. Adding that tag
scaffolds the field names, and an interactive grooming command prompts for every
required value so users need not memorize the storage schema.

### Use Intentions as the only time-allocation model

The existing five-column `Intentions` table already expresses minimum, target,
maximum, and a restricted selector. It becomes the shared input for solver
optimization and heuristic accounting. The fixed `DOMAIN` property, Domain
budgets, generated compatibility intentions, and separate `org-time-budgets`
module are removed rather than deprecated.

Selector evaluation becomes source-aware. Task primitives inspect explicit or
virtual task/project evidence; `calendar-role` inspects imported timed events;
boolean forms combine both recursively. Virtual coarse work inherits project
selector matches. An item may match multiple intentions, and unmatched work
remains valid. The visible heuristic continues to place by hard scheduling rules
and reports intention pressure without turning soft bounds into feasibility
constraints.

Keeping one table avoids two subtly different budgeting interfaces. A separate
selector allocation table was considered, but it would duplicate intention names,
targets, weekly replacement rules, selector parsing, and accounting.

### Derive definition state independently from proof state

The Emacs analysis snapshot owns project inventory and definition diagnostics:

- `INCOMPLETE`: missing/invalid metadata, overallocated effort, or unresolved
  active descendant work.
- `COARSE`: definition-ready with positive virtual effort.
- `DETAILED`: definition-ready, zero virtual effort, and valid executable active
  descendants.

The solver owns feasibility evidence. UI rows combine both only when request IDs
match. This prevents a valid Z3 witness from hiding poor source definition.

### Solve isolated projects and the portfolio from one normalized snapshot

The request contains a canonical project inventory and one task set. TypeScript
constructs solve scopes from it:

- Portfolio scope includes all demand from active definition-ready projects.
- Isolated scope includes one project's tasks and virtual work, transitive
  prerequisites, all calendar/travel/sleep/reserve constraints, and unrelated
  fixed commitments, but excludes unrelated flexible project work.

Project solves run asynchronously with deterministic ordering and bounded
per-scope timeouts. Results share the parent request ID. Repeated constraint
construction is accepted initially for correctness; caching or incremental Z3
contexts can follow profiling.

An Emacs-only grouping of the global witness was considered, but it cannot prove
isolated feasibility and gives no project margins when the global model is
infeasible. Eager isolated solves give the top-level table stable meaning.

### Treat active projects as portfolio commitments

A `#project` with no TODO state or with `TODO`, `NEXT`, or `WAITING` is committed.
`SOMEDAY`, `DONE`, and `CANCELLED` projects are visible but excluded from flexible
portfolio demand. This uses existing Org state rather than adding a parallel
commitment property. Fixed commitments remain globally respected regardless of
their owning project's flexible commitment status.

### Preserve incomplete evidence instead of manufacturing green

The solver may report that the modeled subset is feasible, but the portfolio UI
cannot report green while any committed project is incomplete. Orphan tasks
appear as inventory findings. Untagged headings are intentionally outside project
inventory. Mandatory malformed work continues
to produce `UNKNOWN` rather than being omitted.

### Add structured project attribution to the protocol

The response gains project results and structured conflict attribution. Deadline
margins include `projectId`; conflicts include all derivable task and project IDs
rather than a single source only. Constraints without honest ownership are
`shared`. Core membership is described as involvement, not unique causation.

### Keep scenarios as normalized overlays

Project estimate, deadline, coarse metadata, and commitment changes are added to
the existing scenario object. Scenarios apply before virtual chunks and effective
task deadlines are derived. This ensures baseline and scenario use the same
normalization rules and prevents special-case mutation after model construction.

### Add project-specific quantitative queries incrementally

Project queries reuse bounded binary search and subset minimization patterns from
existing negotiation queries. Maximum effort, minimum work, latest safe start,
and earliest deadline operate on one selected project. Minimal defer set accepts
an explicit candidate list and returns one deterministic cardinality-minimal set;
it does not claim a unique organizational recommendation.

## Risks / Trade-offs

- [Chunk size changes feasibility because chunks are contiguous] -> Require and
  display `PLANNING_CHUNK`; describe the result as conditional on that assumption.
- [Rough estimates create false confidence] -> Display confidence and reserve
  structural-feasibility language for detailed projects.
- [N project solves increase latency] -> Keep solving asynchronous, enforce
  per-scope bounds, cache by request ID, and expose `UNKNOWN` on timeout.
- [Cross-project dependencies blur isolated ownership] -> Include the full
  prerequisite closure and explicitly list borrowed prerequisite projects.
- [Project deadline changes can conflict with earlier task deadlines] -> Preserve
  the earlier task-specific deadline and disclose which deadline governs.
- [Legacy `#project` headings become incomplete] -> Report diagnostics without
  modifying files; users can add metadata gradually.
- [Probable-project heuristics produce noise] -> Keep candidates in a separate
  review section and never auto-promote them.
- [UNSAT cores do not uniquely identify blame] -> Use `CONFLICT-INVOLVED` and
  shared attribution, then offer counterfactual defer queries.

## Migration Plan

1. Introduce project diagnostics and inventory while retaining existing project
   overlays and global solver behavior.
2. Add protocol fields and virtual work behind normalization tests; reject stale
   mixed-version responses through the existing strict schema/version boundary.
3. Add isolated project results and the portfolio review as an additional shadow
   report.
4. Add scenario and negotiation operations after baseline attribution is stable.
5. Review real projects, adding deadlines and coarse estimates gradually. No bulk
   Org migration or automatic metadata insertion occurs.
6. Keep the existing solver report and heuristic visible until the portfolio view
   has been exercised on representative weeks and explicitly accepted.

Rollback consists of removing the new report entry point and ignoring new project
properties; existing Org task records and the visible heuristic remain intact.

## Open Questions

- Whether estimate confidence should later select a configurable overrun stress
  percentage rather than remain disclosure-only.
- Whether milestone-level coarse envelopes should follow after project-level use
  demonstrates a need.
- Whether isolated project proofs should remain eager or become lazy after real
  portfolio sizes and latency are measured.
