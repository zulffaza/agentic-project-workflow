---
description: Execute a project's PLAN.md via orchestrated worktree sub-agents
args: <project-slug> [task-ids | "with <model/agent>"]
agent: pw-orchestrator
---
Follow the `project-workflow` skill. Act as the ORCHESTRATOR — never edit repo code yourself.
Arguments: {{ARGS}} (first token = project slug; optional remainder = task IDs or an override
like "T03 with opus").

Project dir: `{{PW_PROJECTS}}/<slug>`.

1. Read `<project>/task/PLAN.md` fully. **Gate:** confirm an `approved ✅` sign-off in
   `task/review/PLAN.review.md`; if not, STOP and ask. (Per-task review files are **optional** —
   their absence never blocks execution; they only matter when a task is being sent back.) Then:
   `…/{{PW_HOME}}/tooling/pw-lib.sh status <slug> executing`.
2. **Resolve scope — this decides resume behavior, get it right:**
   - **Arguments name specific task IDs** → scope = exactly those tasks (plus an optional `"with
     <model/agent>"` override). This is the deliberate "re-verify just this one" path — run only
     what's named, then stop, whether or not other tasks in the plan are still pending.
   - **No task IDs** → this is a **resume of the whole run**, not "run one task and stop." Scope =
     **every task in the PLAN table whose `Status` is NOT YET `accepted`** — i.e. `todo`,
     `in-progress` (a stale/crashed run), or `verify-failed`. Tasks already `accepted` are left
     completely alone; tasks already `done` (committed + verified, just awaiting my review) are
     also left alone — don't re-run something that already succeeded.
   - **Keep walking the DAG to the end of that scope in this SAME invocation — do not stop after
     handling only one task.** The moment a task you (re)ran reaches `done`, immediately continue:
     spawn whatever depends on it, and any other independent ready task, without waiting for me to
     invoke `/pw-execute` again. A bare `/pw-execute <slug>` should drive the run to the end of
     what's currently ready, once, not one task per invocation.
3. Walk the dependency DAG within that scope. Spawn one executor per task, only once its
   `depends_on` are `done`/`accepted`. Parallelize independent tasks up to the plan's max. Honor
   the plan's **execution routing** and any override in the arguments; record what you used in each
   task's `Actually used:`.
   - **Route each task by its `Branch:`** — this is per-task, so a **mixed** project (fresh tasks +
     adopted branches, see the WORKFLOW "mixed projects" note) is just tasks of both kinds side by side:
     - **Fresh task** (`Branch:` is a new `agent/<slug>/<T0n>`) → **fork a worktree from its
       `Base branch:`**: `git worktree add … -b agent/<slug>/<T0n> origin/<base>`, NOT from the repo's
       current HEAD. Two tasks in the same repo may declare different bases (e.g. `master` and
       `spring3`) — fine, separate branches + worktrees + MRs, parallel. The task's Step 1 spells out
       the exact command; make sure it uses the task's base.
     - **Adopted task** (`Branch:` is an existing in-progress branch from `context/ADOPTED.md`) → do
       NOT create an `agent/…` branch. Per **adopted branch**, make/keep **one shared worktree that
       attaches the existing branch** — `git -C {{PW_REPOS}}/<repo> worktree add
       {{PW_PROJECTS}}/<slug>/worktree/<repo>/<branch-slug> <existing-branch>` (no `-b`).
       **Serialize tasks that share a branch** (one worktree), but **parallelize across different
       adopted branches and all fresh tasks**. If git refuses because a branch is checked out in the
       main repo, tell me to switch that main checkout to another branch first.
4. **How to run each task** — resolve `Execute with: <provider>:<model-or-agent>` via
   `{{PW_HOME}}/tooling/providers.md`. Tasks default to the plan's **Produced by** provider, so most
   run under the agent you're already in:
   - **Same provider you're running under → spawn a native, in-process SUB-AGENT** (NOT a shell
     invocation). Native sub-agents are easier to monitor and cheaper to supervise. If `Execute
     with:` names an agent (an existing one like `code-implementation`, the shipped `pw-executor`,
     or a custom `{{PW_HOME}}/tooling/agents/<name>.md`), spawn that; otherwise spawn a generic
     executor with the named model + the task file as its work order.
   - **Different provider → shell out to that CLI headlessly** (per the registry's invocation
     column), passing the task file as the work order — e.g. a Claude-Code orchestrator hands a
     `kilo:command_code/MiniMaxAI/MiniMax-M3` task to `kilo run --auto -m … --format json`
     (`--auto` is REQUIRED or kilo auto-rejects every permission). **Pipe the prompt via stdin,
     never as a trailing CLI argument** — a long inline argument can vanish entirely across the
     shell-out boundary (confirmed 2026-08-08, kilo→claude: `claude --print` reported no prompt was
     received even though it was right there in the command; the CLI's own syntax was fine in
     isolation). Stdin is immune to this — see `providers.md`'s Cross-provider execution section
     for the verified pattern. **Sub-agents do NOT cross providers:** don't pass `--agent
     pw-executor` (that's the *other* provider's sub-agent you can't reach) — invoke its
     default/primary agent with the task file + skill inline; the executor discipline travels with
     them. Route to a capable model (tiny models stop mid-task). Capture the final text for the
     report, but **confirm the real git artifacts** (branch/commit/Verify), not the CLI's
     self-report.
   - **Either way, tee the run to a log** so I can watch it: append the executor's combined output
     to `{{PW_PROJECTS}}/<slug>/worktree/<T0n>.log`. Tell me the path so I can `tail -f` it in my
     own window. Record it in the task's `## Result → Log:` field.
   - **Apply `Effort:`/`Thinking:`** via the provider's flag (claude `--effort`, kilo
     `--variant` + `--thinking`) per `providers.md`. **Honor version pins** — a full name
     (`claude-opus-4-8`) is passed verbatim, never swapped for the alias. Record resolved flags in
     `Actually used:` (e.g. `claude:claude-opus-4-8 --effort high`). Don't use a bespoke executor
     agent; the discipline comes from the skill + task file. Unverified flags → check `--help` or
     ask me; don't guess.
5. Each executor works ONLY in its own worktree, runs the task's `## Verify`, reports real output,
   and fills the task's `## Result` block (time, log path, commit sha(s), verify outcome).
   **Judging the Verify result decides whether the DAG keeps moving — get this right, it's what
   made a past run stall:**
   - **Confirmed pre-existing/environmental failure** (reproduce it on the *untouched* base branch
     or an unrelated module — it fails there too, so this task's diff isn't the cause) → the task
     still reaches **`Status: done`** (committed + verified), with the caveat spelled out in
     `## Result` (what failed, why it's not a regression, how you confirmed it). **Do not block the
     DAG on it** — continue spawning whatever depends on this task.
   - **A real regression** (fails on this branch, passes on the untouched base) → `Status:
     verify-failed`. This blocks *that task's own dependents* only — every other independent task
     (a different branch, a different repo, an unrelated chain) still proceeds in this same run.
6. **Stop at committed + verified — but only once the WHOLE resolved scope is there, or genuinely
   blocked.** `/pw-execute` does NOT push or open MRs — that's the separate, explicit `/pw-ship
   <slug> [task-ids]` step, so nothing goes outward until I ask. Set each task's `## Result → MR: —`
   (not shipped yet). Keep the dashboard task-status table current and log each action via the
   helper:
   `…/{{PW_HOME}}/tooling/pw-lib.sh log <slug> execute "spawned T0n (provider:model); committed <sha>"`.
   When every task in scope is `done` (or blocked only by a `verify-failed` dependency):
   `…/{{PW_HOME}}/tooling/pw-lib.sh status <slug> review`. Report a clean per-task summary — which
   reached `done`, which are still `verify-failed` and why, which never got a turn because their
   dependency is blocked.

Stop for my review before marking anything `accepted`. Two different re-run paths — don't confuse
them:
- **I explicitly reject one task** after review: I flip it to `Status: verify-failed` and either
  add items to `task/review/T0n.review.md` or just tell you what's wrong — `/pw-review <slug> T0n`
  applies the fix (creating the review file from my feedback if it doesn't exist), then
  `/pw-execute <slug> T0n` re-runs + re-verifies **just that task** in the same worktree, then stops.
- **A bare `/pw-execute <slug>` resume** (no task IDs): per step 2, this walks **everything** not
  yet `accepted` — including any task still `verify-failed` — through to the end of what's ready,
  in one invocation. It is not the same as re-running one task; don't stop early just because the
  run started from a partial/failed state.

When you're ready to publish verified work (and to handle review comments left on an MR), use
`/pw-ship`. **A project does NOT need its MRs merged to be closeable** — see `/pw-close`.
