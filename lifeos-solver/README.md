# LifeOS Z3 Solver

Read-only TypeScript/Z3 backend for the LifeOS Emacs planner. Node 20 or newer
is required; Z3 is embedded as WebAssembly by `z3-solver`, so no system Z3 is
needed.

## Verify

```sh
npm ci
npm run check
npm run build
npm test
npm audit --audit-level=moderate
```

The verified suite is 51/51 Vitest; TypeScript check/build pass, and npm audit
reports zero vulnerabilities.

Run one request:

```sh
npm run solve < test/fixtures/sat.json
```

The CLI reads one request, writes one response, and terminates Z3 worker threads
before exit.

## Current Features

- executable strict `lifeos-planning/v3` Zod request/response schemas, including
  nullable candidate requests and matching candidate response identity;
- canonical project definitions, deterministic virtual coarse work, and
  structured task/project evidence;
- deterministic deadline and safety feasibility with named assumptions;
- contiguous tasks, fixed/unlocked starts, release times, dependencies,
  availability/modes, calendar/travel, sleep, reserve, and intentions;
- lexicographic optional-work and intention optimization;
- baseline/scenario solving, stress classification, margins, structured
  comparison deltas, mapped conflicts, and actionable relaxations;
- isolated project proofs and combined portfolio proofs with modeled-subset,
  borrowed-prerequisite, margin, and conflict disclosure;
- composable project scenarios applied before virtual work and inherited
  deadlines are derived;
- five project negotiations plus the five discretionary/task negotiations, all
  with bounded timeout-aware searches;
- selector-normalized Intentions that can match explicit and virtual work; the
  backend receives matched IDs/evidence rather than reading Org selectors;
- strict scenario/reference/query validation and quantized percentage estimate
  multipliers;
- bounded UNSAT-core shrinking;
- independent verification of every returned feasible model/query witness;
- stable SAT and UNSAT semantic goldens plus generated property tests.

## Layout

- `src/protocol.ts`: executable protocol v3 schemas and field defaults
- `src/candidate.ts`: candidate edits, attribution, omissions, and evidence
- `src/solver.ts`: constraints, optimization, cores, stress, comparisons, queries
- `src/scenario.ts`: composable scenario application
- `src/verify.ts`: independent hard-constraint verification
- `src/cli.ts`: one-request stdin/stdout transport
- `test/fixtures`: SAT and UNSAT request fixtures
- `test/goldens`: stable semantic result projections
- `test/solver.test.ts`: protocol, solver, query, golden, and property tests

Exact semantics are documented in
[`docs/lifeos-solver-protocol.md`](../docs/lifeos-solver-protocol.md).

The backend reads one normalized request and writes one response. It never reads
or writes Org/Calendar files, creates source headings, or persists placements,
scenario changes, project deferrals, or negotiation answers.
