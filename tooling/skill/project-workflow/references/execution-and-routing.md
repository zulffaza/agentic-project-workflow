# Execution phase + model/provider routing (`/pw-execute`)

## Execution phase

**Before routing, skim `REVIEWER-NOTES.md` if it exists** (project root) — anything a past
`pw-reviewer` pass flagged as worth knowing (see `references/review.md`'s AI-assisted review
section). Optional and best-effort: a missing file means no AI review has run yet, not a problem.

Handed `task/PLAN.md`: act as **orchestrator** — read the DAG, spawn one **executor** per task
respecting `depends_on`, keep the dashboard status column + `LOG.md` current. Never edit repo code
as the orchestrator. **Same-provider tasks → spawn a native in-process sub-agent** (natively
monitorable); different-provider → shell out to that CLI headlessly. **Tee each run to
`worktree/<T0n>.log`** so the human can tail it. Each executor works in its own worktree, runs
Verify, reports real output, fills `## Result`. **Execution stops at committed + verified** —
pushing branches and opening MRs is the separate `/pw-ship` step (nothing goes outward until asked).

**Scope + resume (get this right — it's what stalls a run):** task IDs given → run exactly those,
then stop. **No task IDs → resume the WHOLE plan**: every task not yet `accepted` (`todo`,
`in-progress`, `verify-failed`) is in scope; walk the DAG to the end of that scope **in one
invocation** — don't stop after fixing/re-running just one task if more are ready. A Verify
failure confirmed **pre-existing/environmental** (reproduces on the untouched base) still reaches
`Status: done` with the caveat noted, and does NOT block the DAG; only a **real regression** blocks
that task's own dependents — every other independent task still proceeds. An explicit single-task
re-run (`/pw-execute <slug> T0n`, after the human rejects one task — see `references/review.md`)
is the one case that *does* stop after just that task.

**Last step, mandatory:** log each spawn/commit via `pw-lib.sh log`; when every task in scope is
`done` (or blocked only by a `verify-failed` dependency), `pw-lib.sh status <slug> review`. See
`references/conventions-and-gotchas.md` for the helper contract.

## Model / agent per task + provider routing

Every task carries `Execute with: <provider>:<model-or-agent>` + `Why:` + `Story points:`, and
optional `Effort:` (`low`/`medium`/`high`/`xhigh`/`max` → claude `--effort`, kilo `--variant`) +
`Thinking:` (kilo `--thinking`). `PLAN.md` mirrors it in **Execute with** + **SP** columns.
**Default the provider to the plan's "Produced by"** (the agent that did the breakdown) so a run
doesn't force an agent switch; route a task to a different provider only with a stated `Why:`.
**Claude aliases (`opus`/`sonnet`/…) follow the latest version — pin the full name
(`claude-opus-4-8` vs `claude-opus-5`) for reproducibility.** Defaults: `claude:opus`=complex/risky,
`claude:sonnet`=standard (most), `claude:haiku`=trivial mechanical; open-weight models route to
`kilo` via **whichever KiloCode API Providers you configured** (`PW_KILO_API_PROVIDERS` array in
`pw.config.sh` — KiloCode can serve several at once; the maintainer's is `command_code`), e.g.
`kilo:command_code/MiniMaxAI/MiniMax-M3` or `kilo:openrouter/<model>` (`kilo models <provider>` for
each provider's list).

- **Discover real kilo/opencode model ids by querying the live catalog — never recall/guess one
  from memory.** There's no fixed roster to read off anymore; a plausible-looking id can simply
  not exist, or a display name can differ from the real id (verified case: KiloCode's own `auth
  list` shows "Kilo Gateway," but the id it actually resolves under is `kilo`, not `kilo_gateway`
  — `kilo models kilo_gateway` errors). Before writing a task's `Execute with:`:
  ```bash
  kilo models <api-provider>      # once per entry in PW_KILO_API_PROVIDERS (pw.config.sh)
  opencode models                 # opencode manages its own provider config internally
  ```
  Pick an id from that actual output. Claude has no live catalog to query — its fixed alias set
  (`opus`/`sonnet`/`haiku`/`fable` + pinned full names) is already fully documented in the
  registry and `docs/EXECUTION.md`'s table, so there's nothing to discover there.
- **Provider registry** = `agentic-project-workflow/tooling/docs/providers.md`: maps each model/agent
  → the CLI that runs it, and gives that CLI's **headless invocation**. It's the extension point —
  add a row to onboard a new model/provider; nothing hard-codes the list.
- **Model allowlist — check before you write, and again before you run.** No model is off-limits
  by default; `PW_MODEL_ALLOWLIST_<PROVIDER>` in `pw.config.sh` is empty/unset for every provider
  unless the human configured one. Before finalizing a task's `Execute with:` during breakdown,
  AND again right before invoking it during execution, run:
  ```bash
  pw-lib.sh model-check <provider> <model-id>
  ```
  Empty/unset allowlist → always passes (the default — every model allowed). A configured
  allowlist that refuses your choice means pick a different allowed model — never override it or
  run the task anyway.
- **Cross-provider execution:** if a task's provider ≠ the orchestrator's own, the orchestrator
  **shells out to that provider's CLI headlessly**, passing the task file as the work order (Claude
  Code ⇄ KiloCode, and any future provider). The discipline travels with the task (skill + task
  file), not the provider. Unverified headless flags → check `--help` or ask; don't guess.
- The orchestrator spawns (or shells out to) whatever `Execute with:` names — an existing agent
  (e.g. `code-implementation`), the shipped `pw-executor`, or a `provider:model`. Three agents ship
  and are seeded per provider from `tooling/agents/` (`pw-orchestrator`, `pw-executor`,
  `pw-reviewer` — the last is optional, only spawned by `/pw-review <slug> ai …`); add a def there
  only for a genuinely new role no existing agent covers.
- **Agent vs sub-agent — the distinction is load-bearing across providers.** A **sub-agent** is
  spawned *in-process* by an orchestrator of the **same provider** (Claude Task `subagent_type`;
  kilo `mode: subagent`) — a provider can spawn only its OWN sub-agents. `pw-executor` is a
  sub-agent. An **agent** (primary/invocable) is invoked through a provider's CLI — the only unit
  that crosses a provider boundary. `pw-orchestrator` is primary.
- **Cross-provider rule (get this right):** an orchestrator on provider A routing a task to provider
  B **cannot spawn B's sub-agent**. A Claude orchestrator delegating to kilo does NOT name
  `pw-executor` (a kilo sub-agent it can't reach) — it invokes kilo's CLI headlessly with the **task
  file + `project-workflow` skill** as the work order and lets kilo's default agent run it (the
  discipline travels with skill+task, no named agent needed). So `pw-executor` is usable only when
  its own provider is the orchestrator. Routing resolves to exactly one of: **same provider → spawn
  the sub-agent in-process**; **different provider → shell out to that CLI passing the task file
  inline to its default/primary agent** (never `--agent <a-sub-agent>` across the boundary; only a
  provider's own *primary* agents are invocable from outside). When `Execute with:` names an agent,
  resolve its provider: explicit `<provider>:` prefix → else the agent def's own provider → else
  (built-in, no def) the orchestrator's own provider.
- During **breakdown**, set each task's `Execute with:` + `Why:` + `Story points:` (2 SP = 1
  person-day; PLAN carries the manual-effort/timeline estimate). During **execution**, honor any
  override ("run T03 with kilo:command_code/MiniMaxAI/MiniMax-M3") and write it to `Actually used:`.

## Create a worktree

**Fork the new branch from the task's `Base branch:`** (`origin/<base>`), not from whatever HEAD is —
this is what lets two tasks in the SAME repo target different bases (e.g. `master` and `spring3`),
each its own branch + worktree + MR:

```bash
git -C ~/IdeaProjects/<repo> fetch -q origin <base-branch>
git -C ~/IdeaProjects/<repo> worktree add \
  ~/IdeaProjects/projects/<project-slug>/worktree/<repo>/<task-id>-<slug> \
  -b agent/<project-slug>/<task-id>-<slug> origin/<base-branch>
```

(The repo manifest in `PLAN.md` lists each `(repo, base)` pair; a repo may appear on multiple rows.)

## Cross-provider gotchas (verified)

- **KiloCode headless needs `--auto`** — `kilo run` without it auto-*rejects* every permission
  (can't even read the task file). Worktrees are fine via the CLI (`kilo run --auto` verified
  end-to-end); the "auto-approve breaks in worktrees" issue is the **JetBrains plugin**, not the CLI.
- **Pipe the prompt via stdin, never a trailing CLI argument** — a long inline argument can vanish
  entirely across the shell-out boundary (confirmed kilo→claude: `claude --print` reported no
  prompt received even though it was right there in the command; the CLI's own syntax was fine in
  isolation — the loss happens inside the calling tool's own command construction). Stdin is
  immune. Also: headless `claude --print` needs `--dangerously-skip-permissions` or it hangs
  producing no output (no TTY to answer a tool-approval prompt) — same spirit as kilo's `--auto`.
  See `tooling/docs/providers.md`'s Cross-provider execution + Verification-notes sections for the
  full verified pattern.
