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
2. Walk the dependency DAG. Spawn one executor per task, only once its `depends_on` are done.
   Parallelize independent tasks up to the plan's max. Honor the plan's **execution routing** and
   any override in the arguments; record what you used in each task's `Actually used:`.
   - **Adopted (continuation) project** (PLAN says "continuation", or dashboard has an `Adopted:`
     note; units in `context/ADOPTED.md`): do NOT create `agent/…` branches. Per **adopted branch**,
     make/keep **one shared worktree that attaches the existing branch** — `git -C
     {{PW_REPOS}}/<repo> worktree add {{PW_PROJECTS}}/<slug>/worktree/<repo>/<branch-slug>
     <existing-branch>` (no `-b`). **Serialize tasks that share a branch** (one worktree), but
     **parallelize across different adopted branches**. If git refuses because a branch is checked
     out in the main repo, tell me to switch that main checkout to another branch first.
3. **How to run each task** — resolve `Execute with: <provider>:<model-or-agent>` via
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
     (`--auto` is REQUIRED or kilo auto-rejects every permission). **Sub-agents do NOT cross
     providers:** don't pass `--agent pw-executor` (that's the *other* provider's sub-agent you
     can't reach) — invoke its default/primary agent with the task file + skill inline; the executor
     discipline travels with them. Route to a capable model (tiny models stop mid-task). Capture the
     final text for the report, but **confirm the real git artifacts** (branch/commit/Verify), not
     the CLI's self-report.
   - **Either way, tee the run to a log** so I can watch it: append the executor's combined output
     to `{{PW_PROJECTS}}/<slug>/worktree/<T0n>.log`. Tell me the path so I can `tail -f` it in my
     own window. Record it in the task's `## Result → Log:` field.
   - **Apply `Effort:`/`Thinking:`** via the provider's flag (claude `--effort`, kilo
     `--variant` + `--thinking`) per `providers.md`. **Honor version pins** — a full name
     (`claude-opus-4-8`) is passed verbatim, never swapped for the alias. Record resolved flags in
     `Actually used:` (e.g. `claude:claude-opus-4-8 --effort high`). Don't use a bespoke executor
     agent; the discipline comes from the skill + task file. Unverified flags → check `--help` or
     ask me; don't guess.
4. Each executor works ONLY in its own worktree, runs the task's `## Verify`, reports real output,
   and fills the task's `## Result` block (time, log path, commit sha(s), verify outcome).
   Distinguish real regressions from pre-existing/environmental failures (reproduce on the
   untouched base branch).
5. **Stop at committed + verified.** `/pw-execute` does NOT push or open MRs — that's the separate,
   explicit `/pw-ship <slug> [task-ids]` step, so nothing goes outward until I ask. Set each task's
   `## Result → MR: —` (not shipped yet). Keep the dashboard task-status table current and log each
   action via the helper:
   `…/{{PW_HOME}}/tooling/pw-lib.sh log <slug> execute "spawned T0n (provider:model); committed <sha>"`.
   When all requested tasks are committed + verified:
   `…/{{PW_HOME}}/tooling/pw-lib.sh status <slug> review`. If arguments list task IDs, run only those.

Stop for my review before marking anything `accepted`. **If I reject a task:** I flip it to
`Status: verify-failed` and either add items to `task/review/T0n.review.md` or just tell you what's
wrong — `/pw-review <slug> T0n` applies the fix (creating the review file from my feedback if it
doesn't exist), then `/pw-execute <slug> T0n` re-runs + re-verifies in the same worktree.

When you're ready to publish verified work (and to handle review comments left on an MR), use
`/pw-ship`. **A project does NOT need its MRs merged to be closeable** — see `/pw-close`.
