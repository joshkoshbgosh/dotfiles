# OpenCode agents (V2)

Configuration: `.config/opencode/.config/opencode/opencode.json`, installed through Stow.

## Primary agents (paid flagship)

| Agent | Permissions | Delegates to |
| --- | --- | --- |
| `architect` | Read-only design lead; file edits denied | `consultant-astra`, `consultant-free` |
| `foreman` (default) | File edits and dev commands allowed; other shell and MCP actions ask | Free `worker-*` and `router-*` agents |
| `operator` | Edits and dev commands allowed without approval; unknown shell and MCP actions prompt | `consultant-astra` and all free workers/routers |

All paid leads default to `openai/gpt-6-astra`, with no thinking variant override.

## Primary agents (free alternates)

| Agent | Model | Best for |
| --- | --- | --- |
| `architect-free` | Xing4 29B A4B (free, thinking) | Free design lead for reasoning-heavy architecture work; delegates to `consultant-free` |
| `operator-free` | Gemma 4 26B A4B (free, thinking) | Free escalated execution lead; edits and dev commands without approval |

Free alternates mirror their paid counterparts' permission shape but run on zero-cost OpenRouter models.

## Subagents

| Agent | Model | Best for |
| --- | --- | --- |
| `consultant-astra` | gpt-6-astra | Flagship independent analysis, hard debugging, design critique (read-only) |
| `consultant-free` | Xing4 29B A4B (free, thinking) | Free independent analysis and design critique (read-only) |
| `worker-inkling` / `router-lfm` | LFM3-1.7B (free) | Tiny 1.7B — small edits, searches, summaries |
| `worker-mimo` / `router-crouton` | Crouton Alpha (free) | General bounded implementation and test tasks |
| `worker-deepseek` / `router-nemotron-vl` | Nemotron 3.5 Super VL (free) | Vision-language; images/screenshots alongside code |
| `router-flint` | Flint v1.0 (free) | General fallback implementation |
| `router-xing4` | Xing4 29B A4B (free, thinking) | Reasoning-heavy analysis and debugging |
| `router-north-code` | North Mini Code (free, thinking) | Code-specialist implementation and tests |
| `router-gemma` | Gemma 4 26B A4B (free, thinking) | Instruction-following and general reasoning |
| `router-pareto-code` | Pareto Code Router (free) | Code-focused router fallback |
| `router-fusion` | Fusion (free) | General bounded tasks fallback |
| `router-free-router` | Free Models Router (free) | **Ultimate fallback** — meta-router picks best free model |
| `router-bodybuilder` | Body Builder (beta, free) | Last-resort fallback when all others unavailable |

Worker descriptions are starting routing heuristics, not measured performance
claims. All use OpenRouter free models, not the `opencode` provider or OpenCode
Go. Availability and quotas can change; free models may share provider limits.
Leads are instructed to switch workers on availability errors, fall back to
`router-free-router`, then do the work themselves if none is available. This is
agent-driven fallback, not a transport-level retry mechanism.

Subagents cannot delegate. Their permissions are their own. Leads are
instructed not to override child models; subagent permission rules enforce agent
IDs, not model pricing tiers.

## Shared permissions

Every configured working agent can read, search, fetch web content, load skills,
and inspect external directories without prompts. Common shell inspection
commands are allowed. File edits and unknown shell commands ask unless an
agent overrides them. MCP calls generally ask, with Emacs context and visible
text reads allowed. Operator and operator-free escalate edits and known dev
commands to allow, but unknown shell commands and MCP actions still prompt.

Architect, architect-free, and all consultants deny file edits and are
instructed to avoid side effects. Shell allowlists are convenience rules, not a
read-only sandbox; flags and scripts can have side effects. Foreman and workers
trust project scripts run through Bun, npm, and pnpm. Git mutations still ask
on those agents.

## Plugins

Both local plugins (`notify.js`, `stitch-adc.js`) were removed as broken V1
plugins. No `plugins` entries remain in the config. `opencode-mobile@latest`
was dropped from config alongside them; its V2 compatibility has not been
verified.

The built-in Build, Plan, General, and Explore profiles are disabled in favor
of these named roles. Config reloads automatically; `/reload` forces a refresh.

## Migration notes

The config uses native V2 `agents`, ordered `permissions`, `mcp.servers`, and
`plugins`. The published JSON schema validates it.

Model calls and quota fallback have not been exercised by this configuration
migration. Some of the OpenRouter URLs you mentioned are not surfaced in your
OpenCode instance's model catalog; workers use models that were confirmed
available via `opencode models`. The three models that did not appear in your
catalog: `parallel/decisions-fast:free`, `respan/span-01-lite`,
`dots-studio/dots-3-note-preview:free`.
