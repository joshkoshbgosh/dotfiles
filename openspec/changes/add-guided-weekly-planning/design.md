## Context

LifeOS currently reads authoritative recurring and weekly policy from
`planning.org`. Availability is either expanded from the recurring table or
replaced by a dated weekly table, while a matching weekly `Intentions` table and
weekly Solver configuration each replace their recurring table as a whole. The
existing parsers, heuristic forecast, and solver already share restricted
selectors and intention accounting, but users must author the exact Org schema
and selector syntax themselves.

The guided planner crosses the Org parser/writer, calendar-derived busy time,
heuristic forecast, asynchronous solver requests, and user documentation. It
must make common weekly changes easier without creating a second source of truth
or weakening the raw Org workflow.

## Goals / Non-Goals

**Goals:**

- Guide a user from calendar commitments and recurring policy to a reviewable
  weekly draft without requiring Org table or selector syntax.
- Represent weekly availability changes as deterministic additions and
  removals over recurring availability.
- Build canonical restricted selectors from projects, task tags and properties,
  work modes, and calendar roles, with match previews.
- Explain and consistently apply minimum, target, maximum, calendar credit, and
  overlapping-intention semantics.
- Recompute usable capacity and planning pressure immediately while keeping
  asynchronous feasibility evidence fresh and honestly labeled.
- Write only validated, explicitly confirmed canonical Org policy.
- Preserve `planning.org` as authority and retain direct Org editing as the
  advanced path.

**Non-Goals:**

- Automatically scheduling or writing task timestamps.
- Replacing the existing heuristic or solver with a new planning engine.
- Turning intention bounds into hard feasibility constraints.
- Introducing a second persistence format or silently supporting malformed or
  legacy policy.
- Making arbitrary raw selector text the primary guided interaction.

## Decisions

### Use a disposable in-memory weekly draft

The command snapshots the selected week, source markers, source text/hash,
calendar commitments, recurring policy, any existing weekly policy, and current
analysis. Every guided edit updates a draft model, not an Org buffer. The same
normalizers used by production parsing feed the preview, heuristic forecast, and
solver request.

The preview distinguishes recurring values, existing weekly values, draft
changes, and the resulting effective week. Canceling simply discards the draft.
At confirmation, LifeOS verifies that captured sources are unchanged, validates
the complete serialization, and applies one buffer transaction to
`planning.org`; any conflict or validation error leaves source unchanged and
returns the user to review.

Writing incrementally after each prompt was rejected because cancellation could
leave partial policy and asynchronous analysis could observe half-written data.
A separate generated file was rejected because it would compete with canonical
Org authority.

### Give availability exceptions their own overlay table

A week may contain an `Availability exceptions` table with canonical columns:

`| Operation | Date | Start | End | Modes |`

`Operation` is `Add` or `Remove`; dates are within the selected week; times form
a non-empty half-open interval `[Start, End)`; and modes come from the canonical
work-mode vocabulary. Cross-midnight input is split into dated rows. Guided input
uses dates and plain-language mode choices, then serializes this schema.

Effective availability is computed per date and mode:

1. Expand recurring weekday windows into dated intervals.
2. Union all `Remove` intervals and subtract them from the recurring intervals.
3. Union all `Add` intervals into the result.
4. Canonicalize adjacent and overlapping intervals before calendar and other
   fixed constraints are subtracted.

Thus duplicate and same-operation overlaps never create capacity twice, removal
can split a recurring window, and `Add` wins where an add and remove overlap for
the same mode. An exception affects only its listed modes. Different mode totals
are alternative views of shared physical time and MUST NOT be summed as total
capacity.

Retaining complete weekly `Availability` replacement tables was considered, but
it perpetuates copy-and-edit errors. Table-order semantics were rejected because
reordering Org rows would unexpectedly change policy.

### Keep precedence rules explicit by policy kind

Availability exceptions overlay recurring availability. A matching weekly
`Intentions` table remains a complete replacement for recurring intentions, and
a matching weekly Solver configuration remains a complete replacement for its
recurring table. Project properties retain their existing, more-specific
precedence where supported.

If the user does not change intentions, the planner leaves their current source
selection untouched. Once intentions are edited, the draft contains the entire
effective weekly intention set and confirmation writes a complete weekly table.
This prevents a visually partial table from being interpreted as a merge.

A universal merge model was rejected because row identity and deletion would be
ambiguous for intentions and because existing solver-configuration validation
depends on completeness.

### Treat intention bounds as ordered soft preferences

Each bound is optional and uses a non-negative `H:MM` duration; supplied values
must satisfy `minimum <= target <= maximum` for whichever pairs are present.
Zero is an explicit bound, while a blank cell means no bound.

- Minimum is the desired floor. Falling below it is a shortfall, not hard
  infeasibility.
- Target is the preferred allocation. Distance above or below it is reported and
  optimized after bound violations.
- Maximum is the desired ceiling. Exceeding it is an excess, not a prohibition
  on mandatory or calendar work.

Actual allocation includes direct clocked task time and clipped timed calendar
events whose canonical role matches the selector. All-day events, generated
travel, and remote setup can reduce capacity but never credit an intention.
Selected matching work wholly inside the week contributes planned allocation.

An item may match multiple selectors. Its minutes independently credit every
matching intention, so overlapping intention rows are lenses rather than
partition buckets. The underlying event or task consumes physical capacity only
once. The UI discloses overlaps, does not sum intention rows as demand or
progress, and previews the shared matches. For optimization, minimum shortfall
and maximum excess are minimized first across rows, target deviation second;
overlapping rows therefore intentionally express multiple preferences about the
same placement.

Hard min/max constraints were rejected because existing semantics allow fixed
and mandatory work to cross soft bounds without making the schedule falsely
infeasible. Exclusive category accounting was rejected because selectors are
explicitly composable and overlapping.

### Build selectors from typed clauses and preview their meaning

The selector builder offers the existing restricted primitives: task tag,
project tag, project ID, task property, project property, work mode, calendar
role, and task source. Users can combine clauses with all (`and`), any (`or`),
and not (`not`). Values come from current canonical inventories and vocabularies;
property names and values may also be entered explicitly and validated.

Every edit renders a plain-language summary, canonical selector expression, and
current matching tasks, virtual project work, and timed calendar roles. Empty
groups and unsupported forms are rejected before preview or persistence. The
advanced path can still edit the serialized expression directly in
`planning.org`, and the existing restricted parser remains authoritative.

A free-form text-to-selector translator was rejected because ambiguous language
could silently broaden allocation. A fixed set of category checkboxes was
rejected because it could not express the existing composable language.

### Separate immediate indicators from solver proof

Draft edits synchronously recompute effective availability, calendar-subtracted
usable capacity by mode, intention actual/gaps, overlap disclosures, validation
diagnostics, and the deterministic heuristic forecast. Capacity displays include
gross availability, blocked time, and usable time, and state that per-mode values
overlap.

Each edit invalidates any solver result for an older draft identity. Solver
requests are debounced and carry the draft identity; stale responses are
discarded. The UI labels evidence `RUNNING`, `CURRENT`, `STALE`, `LOCAL ONLY`, or
`UNAVAILABLE` and never presents capacity arithmetic or heuristic placement as a
proof. This gives immediate actionable pressure feedback while preserving the
stronger asynchronous feasibility boundary.

Blocking on a solve after every prompt was rejected because it makes interaction
fragile and slow. Reusing an older proof after edits was rejected because its
input no longer describes the preview.

## Risks / Trade-offs

- [Add-wins overlap can surprise a raw editor] -> Document the rule, show
  conflicting add/remove regions in preview, and serialize canonical rows.
- [Per-mode capacity can be mistaken for additive capacity] -> Label modes as
  overlapping views and show unique physical usable time separately.
- [Overlapping intentions can appear to create time] -> Show shared matches and
  prohibit aggregate totals across intention rows.
- [Calendar or Org input changes during a session] -> Hash captured inputs,
  invalidate evidence, and require refresh/review before confirmation.
- [Frequent edits can produce solver churn] -> Debounce requests, identify every
  draft, cancel where possible, and reject stale responses.
- [A guided serializer could diverge from raw parsing] -> Round-trip generated
  text through the canonical parsers before enabling confirmation.

## Migration Plan

1. Add parser and normalization support for `Availability exceptions` while
   retaining recurring availability as the baseline.
2. Add semantic and round-trip tests for exception precedence, bounds,
   selectors, calendar credit, and overlap.
3. Add the in-memory planner, preview, feedback, and confirmation transaction.
4. Route the weekly choice in the settings entry point to the guided planner and
   retain an explicit command for visiting raw policy.
5. Update the manual after behavior is implemented and enable representative-week
   integration tests.

No automatic source migration is required. Existing complete weekly
`Availability` tables must be converted explicitly to recurring policy plus
exceptions before they are removed from the active schema; the migration command
must preview the equivalent effective windows and require confirmation. Rollback
is removal of the guided entry point and exception reader after converting any
persisted exception tables back to complete weekly availability tables.

## Open Questions

None. The table schema, precedence, bounds, overlap, feedback, and write boundary
are defined above.
