# LifeOS Org Planning

LifeOS is an Org-mode planning system for capture, grooming, dependency
analysis, calendar integration, weekly intentions, and reviewable scheduling.
Org files under `~/Work/lifeos/` are authoritative and are not stored here.

The deterministic four-week heuristic remains the visible forecast. A
TypeScript/Z3 planner runs asynchronously and provides a structured report,
scenarios, negotiation queries, heuristic comparisons, and complete schedule
candidates. Analysis and candidate edits are read-only. Only explicit guarded
acceptance can replace the machine-owned flexible future plan in `planning.org`;
neither planner changes source tasks, projects, calendars, or planning policy.

## Install

```sh
cd ~/Work/dotfiles/config
stow -t ~ emacs
```

`my/lifeos-dir` is configured in
`config/emacs/.config/emacs/startup/paths.el`. The agenda includes
`inbox.org`, `projects.org`, `habits.org`, `routines.org`, `journal.org`,
`done.org`, `planning.org`, and `calendar.org`.

## Task Model

An executable task is a leaf TODO heading marked `#task`:

```org
* TODO [#A] Write essay #task
DEADLINE: <2026-10-16 Fri>
:PROPERTIES:
:ID:              stable-id
:EFFORT:          6:00
:ORIGINAL_EFFORT: 6:00
:IMPACT:          High
:WORK_MODE:       Deep
:END:

Depends on [[depends-on:research-id][Finish research]].
```

- Outline hierarchy means composition; `depends-on` means execution order.
- Executable tasks cannot contain TODO descendants.
- `EFFORT` is expected total effort. Remaining work is `EFFORT` minus direct
  clocks.
- A timed `SCHEDULED` timestamp is fixed unless a scenario explicitly unlocks
  it. Solver placements are virtual.
- A future `WAIT_UNTIL` on mandatory `WAITING` work becomes `releaseTime`; the
  task cannot start before it. Missing or expired release evidence leaves
  mandatory waiting unresolved and assurance `UNKNOWN`.

## Project Model

A recognized project is only a heading you explicitly mark `#project`; LifeOS
does not infer projects from deadlines, hierarchy, or descendant tasks. Adding
the tag scaffolds an ID and the project property names after editing or before
save. Run `my/lifeos-groom-project` (`M-; n p m`) to answer plain-language
prompts instead of remembering those names.

A project with no TODO
state, or with `TODO`, `NEXT`, or `WAITING`, is committed; `SOMEDAY`, `DONE`,
and `CANCELLED` projects remain visible but are uncommitted. A committed project
needs a stable `ID`, a parseable `DEADLINE`, and a positive, 15-minute-aligned
`PROJECT_EFFORT` before it can receive a positive proof.

`PROJECT_EFFORT` is the expected total project effort, not extra work above its
tasks:

```text
explicit effort = sum(EFFORT of every executable descendant, including completed tasks)
virtual effort  = max(PROJECT_EFFORT - explicit effort, 0)
remaining work  = active explicit remaining effort + virtual effort
```

Completed task estimates continue to consume the envelope. If explicit effort
exceeds it, every explicit task remains demand and the project is `INCOMPLETE`.
Positive virtual effort additionally requires `DEFAULT_WORK_MODE`, a positive
15-minute-aligned `PLANNING_CHUNK`, and `ESTIMATE_CONFIDENCE` of `Low`, `Medium`,
or `High`. It becomes deterministic, mandatory virtual chunks in normalized
solver input only; the final chunk may be smaller.

Definition and proof are separate:

- `INCOMPLETE`: missing/invalid required metadata, overallocated effort, or
  unresolved active descendant work.
- `COARSE`: valid definition with positive virtual effort.
- `DETAILED`: zero virtual effort and all active descendants are valid executable
  tasks.
- `CAPACITY FEASIBLE`: a coarse project's explicit and virtual work fits under
  the stated chunking and estimate assumptions; unknown structure is not proved.
- `STRUCTURALLY FEASIBLE`: a detailed project's valid task graph fits.

### Coarse To Detailed

Start with a coarse 12-hour project. The 3-hour planning chunk produces four
virtual chunks:

```org
* TODO Publish field guide #project
DEADLINE: <2026-11-20 Fri>
:PROPERTIES:
:ID:                  field-guide
:PROJECT_EFFORT:      12:00
:DEFAULT_WORK_MODE:   Deep
:PLANNING_CHUNK:      3:00
:ESTIMATE_CONFIDENCE: Medium
:END:
```

After adding two explicit tasks totaling 5 hours, normalization produces only
7 hours of virtual residual (`3:00`, `3:00`, `1:00`). Total project effort stays
12 hours, not 17:

```org
* TODO Publish field guide #project
DEADLINE: <2026-11-20 Fri>
:PROPERTIES:
:ID:                  field-guide
:PROJECT_EFFORT:      12:00
:DEFAULT_WORK_MODE:   Deep
:PLANNING_CHUNK:      3:00
:ESTIMATE_CONFIDENCE: Medium
:END:
** TODO [#A] Research sources #task
:PROPERTIES:
:ID:              field-guide-research
:EFFORT:          3:00
:ORIGINAL_EFFORT: 3:00
:WORK_MODE:       Deep
:IMPACT:          High
:END:
** TODO [#A] Draft guide #task
:PROPERTIES:
:ID:              field-guide-draft
:EFFORT:          2:00
:ORIGINAL_EFFORT: 2:00
:WORK_MODE:       Deep
:IMPACT:          High
:END:
```

Complete the breakdown by adding the remaining 7-hour child under the same
project:

```org
** TODO [#A] Revise and publish #task
:PROPERTIES:
:ID:              field-guide-publish
:EFFORT:          7:00
:ORIGINAL_EFFORT: 7:00
:WORK_MODE:       Deep
:IMPACT:          High
:END:
```

The executable descendants now total `3:00 + 2:00 + 7:00 = 12:00`, so virtual
effort becomes zero and the valid project becomes `DETAILED`. Explicit tasks
replace virtual residual; they are never added on top of the full envelope.

## Daily Commands

| Command | Purpose |
|---|---|
| `my/lifeos-scaffold-task` | Add task identity and planning placeholders |
| `my/lifeos-groom-task` | Fill required metadata interactively |
| `my/lifeos-scaffold-project` | Explicitly mark a heading as a project and add its planning placeholders |
| `my/lifeos-groom-project` | Fill project deadline, effort, mode, chunk, and confidence interactively |
| `my/lifeos-set-remaining-effort` | Set remaining work while preserving original effort |
| `my/lifeos-effort-anchor-preview` | Read-only list of tasks that could get an initial effort anchor |
| `my/lifeos-effort-anchor-all` | Anchor current `EFFORT` as remaining effort for every eligible task |
| `my/lifeos-break-down-task` | Convert aggregate work into executable leaves |
| `my/lifeos-add-dependency` | Add a cycle-checked prerequisite |
| `my/lifeos-open-ready-task` | Visit a ready task |
| `my/lifeos-open-blocked-task` | Visit a blocked task |
| `my/lifeos-explain-at-point` | Explain task findings, cached forecast conflicts, or project metrics |
| `my/lifeos-next-diagnostic` | Visit the next task or project diagnostic overlay |
| `my/lifeos-previous-diagnostic` | Visit the previous task or project diagnostic overlay |
| `my/lifeos-needs-grooming` | Open the grooming report |

Diagnostic navigation visits task and project diagnostic overlays. Project
summaries and metrics remain available at point through
`my/lifeos-explain-at-point`.

An initial effort anchor records the task's current `EFFORT` as remaining effort
at one shared instant; it only applies to active tasks with a positive `EFFORT`,
no clock entries, and no existing episode. `my/lifeos-effort-anchor-preview` is
read-only, and `my/lifeos-effort-anchor-all` asks for confirmation before writing
the append-only `LIFEOS_EFFORT` drawer.

## Solver Commands

| Command | Purpose |
|---|---|
| `my/lifeos-solver-show-shadow-result` | Open the structured read-only baseline/scenario report |
| `my/lifeos-solver-show-report` | Alias for the structured report |
| `my/lifeos-solver-show-raw-json` | Open the last accepted response as formatted JSON |
| `my/lifeos-solver-show-discrepancies` | Open the report at the heuristic/solver comparison |
| `my/lifeos-solver-show-portfolio-review` | Open the read-only project portfolio review |
| `my/lifeos-solver-scenario-menu` | Compose, clear, or run an ephemeral scenario |
| `my/lifeos-solver-negotiate` | Run a task/discretionary or project negotiation query |
| `my/lifeos-solver-visit-source` | Visit a captured source ID |

The scenario menu composes busy reservations, task estimate replacements,
intention-bound changes, fixed-commitment unlocks, and project changes to total
effort, deadline, commitment, default work mode, planning chunk, or estimate
confidence. Project changes apply before inherited deadlines and virtual chunks
are derived. Deltas stay in memory and a query can target baseline or scenario.
Running, comparing, or querying never persists anything.

From a current Portfolio Review, press `s` to open one complete schedule
candidate. Its local controls are `n`/`p` navigation, `RET` details, `v` source,
`m` exact placement, `x` exclusion, `e` draft-only estimate, `u` candidate undo,
`r` stale-candidate close followed by Portfolio refresh and `s`, `a` complete
acceptance review, `d` discard, `R` bounded
previous-plan restore, `h` help, and `q` quit. See the action-first
`~/Work/lifeos/docs/lifeos/schedule-candidates.org` manual chapter.

Convenience query commands are also available:
`my/lifeos-solver-negotiate-maximum-deadline-only`,
`my/lifeos-solver-negotiate-maximum-safe`,
`my/lifeos-solver-negotiate-minimum-required-work`,
`my/lifeos-solver-negotiate-latest-safe-start`, and
`my/lifeos-solver-negotiate-minimal-unlock-set`.

The five project negotiations are maximum project effort, minimum required
project work in a window, latest safe project start, earliest feasible project
deadline, and a deterministic cardinality-minimal defer set from explicit
candidates. Each result states baseline/scenario scope and, where applicable,
`deadline-only` or `safe` assurance. Bounds are 15-minute aligned and `UNKNOWN`
returns no optimistic partial answer.

Leader bindings use `M-;` followed by:

| Keys | Command |
|---|---|
| `n p e` | Explain at point |
| `n p n` | Next task or project diagnostic |
| `n p p` | Previous task or project diagnostic |
| `n p s` | Solver report |
| `n p j` | Solver raw JSON |
| `n p d` | Solver discrepancies |
| `n p P` | Portfolio feasibility review |
| `n p m` | Groom project metadata at point |
| `n p S` | Scenario menu |
| `n p q` | Negotiation query |
| `n p g` | Incremental calendar fetch |
| `n p G` | Full calendar refresh |

## Weekly Planning

`planning.org` has `Recurring defaults` and optional `#week` headings keyed by
exact `WEEK_START`. A matching week heading selects complete weekly
Availability, Intentions, and Solver configuration tables when present;
otherwise recurring tables apply. Selected tables replace recurring rows as a
whole and never merge. A weekly Solver configuration table must contain every
required key.

### Intentions

The exact header and a complete example are:

```org
** Intentions
| Name           | Min  | Target | Max  | Selector                                      |
| Philosophy     | 6:00 | 10:00  |      | (project-tag "philosophy")                   |
| Essay 1        | 4:00 | 8:00   |      | (project-id "essay-1-project-id")            |
| Exercise       | 3:00 | 5:00   | 7:00 | (tag "exercise")                             |
| Deep study     |      | 8:00   |      | (and (work-mode "Deep") (project-tag "study")) |
| Study time     |      | 12:00  |      | (or (project-tag "study") (calendar-role "study")) |
```

Supported selector forms are `(tag "...")`, `(project-tag "...")`,
`(project-id "...")`, `(prop "KEY" "VALUE")`,
`(project-prop "KEY" "VALUE")`, `(work-mode "...")`,
`(calendar-role "...")`, `(source task)`, and nested
`(and ...)`, `(or ...)`, and `(not ...)`. Parsing disables reader evaluation.
Selectors are source-aware and boolean forms recurse over each source: task
primitives inspect explicit task or owning-project evidence, including virtual
work; `calendar-role` inspects calendar events. Thus the final example credits
both project work and timed matching events.

Bounds are optional 15-minute-aligned `H:MM` durations. Minimum and maximum are
strong preferences, target is the ideal, and hard commitments may violate them.
Intentions overlap: one placement credits every matching row and capacity is not
double-counted. Direct clocks in the current week reduce desired work. A
matching recursive selector credits clipped timed event minutes; all-day events,
generated travel, and remote setup never count. If no weekly or recurring
Intentions table exists, work remains schedulable and reports say `No allocation
targets are configured.`

A temporal waiting release is an Org timestamp property, for example:

```org
:WAIT_UNTIL: <2026-10-15 Thu 09:00>
```

Only a parseable future value becomes a solver release time.

### Solver Configuration

The parser requires the exact `Key | Value` header, every fixed key exactly
once, strict `yes`/`no`, 15-minute alignment, and optional
`Travel default: TYPE` rows. Exact duplicate keys are rejected. This complete
table contains conservative provisional review values, not personally approved
policy:

```org
** Solver configuration
| Key                                           | Value       |
| Sleep earliest start                          | 22:00       |
| Sleep latest end                              | 09:00       |
| Sleep minimum                                 | 8:00        |
| Default safety buffer                         | 24:00       |
| Daily reserve                                 | 1:00        |
| Weekly reserve                                | 4:00        |
| Reserve block                                 | 1:00        |
| Known travel default                          | 0:45 / 0:45 |
| Unknown travel default                        | 1:00 / 1:00 |
| Remote setup                                  | 0:15        |
| Stress estimate overrun enabled               | yes         |
| Stress estimate overrun percent               | 25          |
| Stress lose largest Deep window enabled       | yes         |
| Stress unexpected appointment enabled         | yes         |
| Stress unexpected appointment duration        | 1:00        |
| Travel default: campus                        | 0:30 / 0:30 |
```

Without an Org table, code fallbacks use the same sleep, buffer, reserve, known
travel, unknown travel, and remote setup values shown above, but all stress
profiles are disabled and their percentage/duration values are unset. These are
chosen implementation defaults, not user-approved policy. Project property
`SAFETY_BUFFER` overrides the default buffer.

### Existing Reports

```org
#+BEGIN: lifeos-remaining-by-intention :week 2026-10-12
#+END:

#+BEGIN: lifeos-intention-ledger :week 2026-10-12
#+END:

#+BEGIN: lifeos-critical-paths
#+END:

#+BEGIN: lifeos-forecast :start 2026-10-12 :weeks 4
#+END:
```

Use Monday for forecast `:start`. The heuristic greedily places one contiguous
block per valid task. Intentions report independent, possibly overlapping views
of remaining, clocked, calendar, fixed, and proposed time; they do not duplicate
physical capacity or override hard scheduling rules.

## Assurance

- `PROVEN FEASIBLE` means a model witness satisfies known hard constraints.
- `PROVEN INFEASIBLE` means no witness exists under the stated assumptions.
- `UNKNOWN` means missing/invalid mandatory input, unresolved waiting,
  insufficient or stale coverage, timeout, or failed independent verification
  prevents proof. It is never treated as feasible.
- `SAFE` means configured deadline buffers and reserve blocks also fit.
- `TIGHT` means deadlines fit but configured safety constraints do not.
- `RESILIENT` means every configured stress profile remains deadline-feasible.
- `FRAGILE` means at least one configured stress profile is infeasible. An
  unknown stress result leaves resilience unset.
- A coarse positive project proof is `CAPACITY FEASIBLE`; only detailed valid
  task structure can be `STRUCTURALLY FEASIBLE`.

Calendar assurance requires a successful org-gcal fetch no older than 30
minutes and explicit imported coverage through the complete assurance horizon.
Availability must cover the same horizon. Missing safety policy leaves safety
unset rather than manufacturing `SAFE`.

## Calendar And Travel

`my/org-gcal-fetch` imports incrementally with a 60-day future lookahead;
`my/org-gcal-full-refresh` clears tokens and imports again. Run an explicit fetch
once after Emacs starts to unlock credentials and enable polling for that
session. Polling then repeats every 15 minutes without permitting password or
browser prompts. Overlapping fetches are skipped; successful changed imports are
normalized, saved, and invalidate planning analysis. If unattended token refresh
fails, the dashboard reports `AUTH REQUIRED`; run an explicit fetch to recover.

Busy timed events block their interval and busy all-day events block the day.
For solver travel, use:

```org
:ATTENDANCE: remote
```

or:

```org
:ATTENDANCE: in-person
:GCAL_EVENT_TYPE: campus
:TRAVEL_BEFORE: 0:30
:TRAVEL_AFTER: 0:45
```

`ATTENDANCE` accepts only `remote` or `in-person`. Legacy `TRAVEL_REQUIRED=yes`
maps to in-person and `no` maps to remote. Remote events receive configured
setup before the event. In-person travel precedence is per-event override,
typed `Travel default: TYPE`, then unknown-location default. Missing attendance
conservatively assumes in-person travel and is disclosed. Invalid or incomplete
required travel data makes assurance unknown.

## Guarded Write Boundary

Solver code reads normalized data through Emacs and communicates through one
`lifeos-planning/v3` JSON request/response, including strict nullable candidate
identity for ordinary solves and revision-keyed schedule-candidate edits.
TypeScript never reads Org files.
Virtual work, portfolio proofs, placements, scenarios, project assumption
changes, deferrals, unlocks, intention changes, negotiation answers, candidate
generation, and candidate manipulation are not written to Org or Calendar. The
sole planning exception is explicit complete candidate acceptance, or its
bounded guarded restore. It validates current evidence and authoritative input,
then atomically replaces only the machine-owned `Accepted schedule` subtree in
`planning.org`; failure leaves the prior plan unchanged. The calendar importer
separately writes its normal import file.

## Verification

From the repository root:

```sh
emacs --batch -Q \
  -l config/emacs/.config/emacs/org/lifeos-planning-test.el \
  -l config/emacs/.config/emacs/org/lifeos-supertag-test.el \
  -l config/emacs/.config/emacs/org/org-gcal-test.el \
  -l config/emacs/.config/emacs/org/lifeos-schedule-test.el \
  -l config/emacs/.config/emacs/org/lifeos-solver-test.el \
  -l config/emacs/.config/emacs/org/lifeos-agenda-test.el \
  -f ert-run-tests-batch-and-exit

emacs --batch -Q \
  -l config/emacs/.config/emacs/org/lifeos-doc-test.el \
  -f ert-run-tests-batch-and-exit

cd lifeos-solver
npm ci
npm run check
npm run build
npm test
npm audit --audit-level=moderate
```

Verified counts on 2026-10-19 are **167/167 ERT**, **8/8 documentation ERT**, and
**51/51 Vitest**. TypeScript check and build pass, and npm audit reports zero
vulnerabilities.

## Documentation

- [`PLAN.md`](PLAN.md): active review and rollout handoff
- [`docs/lifeos-current-system.md`](docs/lifeos-current-system.md): implemented
  architecture and behavior
- [`docs/lifeos-solver-design.md`](docs/lifeos-solver-design.md): implemented
  design and retained rollout boundary
- [`docs/lifeos-solver-protocol.md`](docs/lifeos-solver-protocol.md): exact v3
  request, result, and query semantics
- [`lifeos-solver/README.md`](lifeos-solver/README.md): solver package operation
