## Context

LifeOS currently derives an effective deadline for each task from its own and its
owning project's deadline. At the lower-bound side, only a future `WAIT_UNTIL` on
a `WAITING` task becomes a solver `releaseTime`; projects have no equivalent.
The `latest-safe-project-start` negotiation temporarily raises releases on
non-fixed project tasks, but it is not stored project input, excludes fixed work,
and disappears after the query.

Dependencies are likewise task-only. A task in one project may depend on a task
in another, and isolated proof follows that task closure, but this does not mean
that all work in the prerequisite project must finish. It also cannot represent
whole-project ordering while either project contains virtual coarse work.

The change crosses Org source conventions, Emacs validation and forecasting, the
strict JSON protocol, scenario derivation, Z3 constraints, proof scoping,
independent verification, and portfolio UI. Solver and forecast operations must
remain read-only; only explicit grooming and dependency-editing commands may
write Org metadata.

## Goals / Non-Goals

**Goals:**

- Represent an optional hard lower bound for all remaining project-owned work.
- Represent explicit whole-project finish-to-start dependencies.
- Include explicit and coarse virtual demand in release and dependency proofs.
- Keep task-local releases and task dependencies independently meaningful.
- Produce `UNKNOWN` for incomplete prerequisite evidence rather than false green.
- Preserve guided metadata entry and source-linked red-green remediation.
- Keep solver answers independently verifiable and scenario-safe.

**Non-Goals:**

- Inferring start dates or project dependencies from hierarchy, prose, or task
  links.
- Treating the first proposed placement as a persisted project start date.
- Automatically changing project state, accepting scenario changes, or writing
  solver placements.
- Inventing an order among virtual chunks within one coarse project.
- Replacing precise task-to-task dependencies with project dependencies.
- Modeling partial project gates or milestone-to-milestone dependencies in this
  change.

## Decisions

### Use an optional `NOT_BEFORE` project property

`NOT_BEFORE` is a lower bound, not a fixed start. A date-only Org timestamp means
local midnight at the beginning of that date; a timed timestamp means that exact
local minute. An absent value means the project is immediately releasable, a past
value is valid but nonbinding, and a malformed value makes the project definition
`INCOMPLETE`.

The bound applies to every selected explicit or virtual task owned by the
project, including fixed tasks. A fixed task before the bound therefore exposes
a contradiction. Borrowed prerequisite work belongs to its own project and may
occur before the dependent project's bound.

This is separate from task `WAIT_UNTIL`: task waiting expresses a local gate and
project not-before expresses a common project gate. The effective lower bound is
the maximum of both. Overloading `SCHEDULED` was rejected because timed scheduled
work is an exact fixed start. Overloading project `WAIT_UNTIL` was rejected
because its current meaning is tied to unresolved `WAITING` tasks and future-only
release evidence.

### Use a dedicated `project-depends-on` link type

A project prerequisite is stored in the dependent project's direct body:

```org
Depends on [[project-depends-on:PROJECT-ID][Prerequisite project]].
```

The dedicated type keeps project IDs out of the task-only `depends-on` graph and
makes target validation and editing unambiguous. A project edge means all
remaining required work in every prerequisite project must finish before any
remaining work owned by the dependent project starts.

Virtual chunks remain mutually unordered. Project ownership supplies the
whole-project gate without creating durable links to generated virtual IDs.

### Treat prerequisite closure as required demand

A committed dependent project pulls the complete transitive prerequisite-project
closure into isolated and portfolio proof even when a prerequisite is otherwise
`SOMEDAY` or uncommitted. This mirrors task prerequisite closure: declaring the
edge asserts that the prerequisite work is required for the commitment.

A `DONE` prerequisite with no remaining demand satisfies the edge. A `CANCELLED`
prerequisite does not satisfy a committed dependent and is a project-definition
error. An incomplete prerequisite makes the dependent proof `UNKNOWN`; it is not
silently omitted. Missing targets, self-links, duplicates, pure project cycles,
and cycles formed jointly with cross-project task edges are structural errors.

Simply excluding uncommitted prerequisites was rejected because it would produce
optimistic proofs. Automatically changing their Org state was rejected because
analysis is read-only.

### Model project bounds and edges as first-class solver constraints

The protocol carries project `notBefore` and `prerequisiteProjectIds`. The solver
derives project start/end expressions from selected owned tasks, including
virtual work, and enforces project release and finish-to-start constraints with
stable project/task attribution. It does not expand persistent Org relations into
generated virtual task IDs.

Independent verification checks every placement against its owning project bound
and checks that the latest prerequisite-project completion is no later than the
earliest dependent-project start. Missing required predecessor work is also
verified, not assumed.

### Preserve raw bound provenance in protocol v3

The current normalized task stores one effective deadline plus a single source
label. That cannot correctly recompute `min(task deadline, project deadline)`
after a project scenario when both values exist. Adding release inheritance with
the same pattern would repeat the defect.

Protocol v3 preserves task-local deadline/release inputs while project bounds live
on the project record. Effective constraints are derived after scenario project
changes. The same rule computes deadline as the minimum applicable upper bound and
release as the maximum applicable lower bound. Protocol and solver versions are
bumped because schemas and proof semantics are strict and breaking.

### Make scenarios and start negotiation use project input

Project scenarios can set, replace, or clear `notBefore`; absence means preserve
baseline while explicit null means clear it. Project dependencies remain source
structure and are not scenario-editable in this change.

`latest-safe-project-start` is defined precisely as the latest aligned project
not-before bound that preserves the requested assurance. It changes the project
field during search rather than rewriting task releases, so explicit, virtual,
and fixed owned work all participate. Queries against absent, incomplete, or
unmodeled target demand return `UNKNOWN`.

### Keep the visible forecast honest about its boundary

The heuristic honors project not-before bounds for explicit work. For a detailed
project dependency it schedules prerequisite-project explicit work before
dependent work. If a prerequisite contains virtual residual that the heuristic
does not place, dependent explicit work is reported as unresolved instead of
being placed early. Solver portfolio proof remains the authoritative coarse
capacity result, and reports disclose this boundary.

### Extend guided project interaction

Project scaffolding adds the optional field name without forcing a value. Guided
grooming asks whether work may begin immediately or after a date; users do not
need to remember `NOT_BEFORE`. A separate project-dependency command selects only
valid explicit projects, prevents cycles before writing, and creates the typed
link. Portfolio rows and drilldowns show the bound, prerequisites, dependents,
closure, and actionable structural errors.

## Risks / Trade-offs

- [Whole-project finish-to-start may be more restrictive than reality] -> Keep
  task dependencies for precise overlap and describe project edges as a deliberate
  coarse gate.
- [Pairwise project constraints can grow with task counts] -> Derive aggregate
  project start/end expressions and profile large portfolios before rollout.
- [Uncommitted prerequisite closure may surprise users] -> Disclose forced
  prerequisite demand and commitment state in isolated and portfolio drilldowns.
- [Coarse prerequisite work lacks internal order] -> Preserve `CAPACITY FEASIBLE`
  language and never claim structural feasibility from virtual chunks.
- [Mixed task/project cycles are difficult to explain] -> validate a projected
  ownership graph before solving and provide source-linked cycle paths.
- [Date-only bounds are timezone-sensitive] -> normalize using the same local
  timezone and minute conversion as deadlines, and test daylight-saving edges.
- [Protocol migration can invalidate last-good responses] -> reject v2 responses
  explicitly, clear incompatible cached results, and retain no compatibility
  translation unless a concrete external consumer is identified.
- [Existing project-work negotiation verification counts borrowed placements] ->
  fix project-specific witness accounting before dependency closure expands.

## Migration Plan

1. Add failing Emacs and TypeScript tests for release composition, provenance,
   project graph validation, coarse prerequisite closure, and verifier mutations.
2. Introduce protocol v3 and update fixtures before enabling new source metadata.
3. Add source parsing, scaffolding, grooming, dependency commands, and diagnostics.
4. Implement scenario derivation, solver constraints, proof scoping, attribution,
   and independent verification.
5. Update the heuristic and portfolio UI, then run real-data read-only shadow
   comparisons with Org hash checks.
6. Document the new property/link and explicitly review policy and query wording.
7. Roll back by removing new source metadata and reverting the v3 consumer and
   producer together; no solver-generated data requires migration.

## Open Questions

- Whether a `DONE` prerequisite with stale nonzero project effort should be
  accepted as completed evidence or diagnosed for effort reconciliation. The
  conservative implementation should diagnose it until an explicit policy is
  approved.
