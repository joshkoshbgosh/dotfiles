## Why

LifeOS can prove whether project work fits before a deadline, but it currently
assumes every project may begin immediately and can express ordering only between
individual explicit tasks. This overstates feasibility when a project is gated by
a real not-before date or by completion of another project, especially while one
or both projects still contain coarse virtual work.

## What Changes

- Add an optional project not-before timestamp that acts as a hard lower bound on
  all remaining explicit and virtual work owned by that project.
- Compose project and task release bounds without weakening either one, and make
  fixed work before a project release an explicit conflict.
- Add explicit project-to-project finish-to-start dependencies with validation,
  cycle detection, prerequisite closure, source navigation, and portfolio
  attribution.
- Include complete prerequisite-project demand in isolated and combined proofs,
  including coarse virtual work; incomplete prerequisite evidence produces
  `UNKNOWN` rather than an optimistic proof.
- Extend guided project grooming, project dependency editing, portfolio review,
  scenarios, negotiations, and the visible forecast with the new constraints.
- Correct project deadline/release provenance so project scenarios recompute
  effective task bounds when task-local and project-level bounds coexist.
- **BREAKING**: bump the strict planning protocol because project records, task
  bound provenance, scenario changes, proof scoping, and verification semantics
  change.

## Capabilities

### New Capabilities

- `project-release-gates`: Persistent project not-before bounds, composed task
  releases, scenario behavior, forecasting, verification, and UI disclosure.
- `project-dependency-graph`: Whole-project finish-to-start dependencies,
  structural validation, prerequisite demand closure, proof semantics, and
  project-level editing/navigation.

### Modified Capabilities

None. There are no archived baseline capability specifications in
`openspec/specs/`; this proposal builds on the active portfolio change.

## Impact

- Emacs project scaffolding/grooming, project records and diagnostics, task-bound
  derivation, visible forecasting, scenario/query builders, and portfolio UI.
- The TypeScript protocol, scenario regeneration, Z3 encoding, isolated and
  portfolio scoping, conflict attribution, negotiation semantics, and independent
  result verification.
- Org metadata conventions and link types for project releases and project
  prerequisites.
- Protocol fixtures, semantic goldens, ERT/Vitest coverage, and all LifeOS solver
  documentation.
