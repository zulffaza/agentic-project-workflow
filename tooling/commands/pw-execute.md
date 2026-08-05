---
description: Execute a project's PLAN.md via orchestrated worktree sub-agents
args: <project-slug> [task-ids | "with <model/agent>"]
agent: pw-orchestrator
---
Follow the `project-workflow` skill. Act as the ORCHESTRATOR — never edit repo code yourself.
Arguments: {{ARGS}} (first token = project slug; optional remainder = task IDs or an override
like "T03 with opus").

Project dir: `{{PW_PROJECTS}}/<slug>`.

1. Read `<project>/task/PLAN.md` fully. Confirm an `approved ✅` sign-off in
   `task/review/PLAN.review.md`; if not, STOP and ask. Then:
   `…/{{PW_HOME}}/tooling/pw-lib.sh status <slug> executing`.
2. Walk the dependency DAG. Spawn one executor per task, only once its `depends_on` are done.
   Parallelize independent tasks up to the plan's max. Honor the plan's **execution routing** and
   any override in the arguments; record what you used in each task's `Actually used:`.
3. Execute each task with its `Execute with: <provider>:<model-or-agent>`. Resolve the provider
   via `{{PW_HOME}}/tooling/providers.md`:
   - **If it names an agent** (built-in or a `sub-agent/<name>.md`), resolve the agent's provider
     first: explicit `<provider>:` prefix → else the agent def's `Provider:` → else the
     orchestrator's own provider; apply the agent's `Default model`/`Default effort` unless the
     task overrides. When shelling out to another provider, use its native-agent flag if the def
     names one (`kilo run --agent <name> -m <model> …`), else pass the agent brief + task file inline.
   - **Same provider you're running under** → spawn a normal in-process sub-agent with that
     model/agent.
   - **Different provider** → invoke that provider's CLI **headlessly** (per the registry's
     invocation column), passing the task file as the work order — e.g. a Claude-Code orchestrator
     hands a `kilo:command_code/MiniMaxAI/MiniMax-M3` task to `kilo run --auto -m … --format json`
     (`--auto` is REQUIRED or kilo auto-rejects every permission), or a KiloCode orchestrator
     shells out to `claude -p`. Route to a capable model (tiny models stop mid-task). Capture the
     final text part for the report, but **confirm the real git artifacts** (branch/commit/Verify),
     not just the CLI's self-report.
     The discipline travels with the task (skill + task file), not the provider. Capture the CLI's
     output into the task `## Result` and record the provider in `Actually used:`.
   - **Apply the task's `Effort:`/`Thinking:`** by mapping to the provider's flag (claude
     `--effort`, kilo `--variant` + `--thinking`) per `providers.md`. **Honor version pins** — if
     `Execute with:` uses a full name (`claude-opus-4-8`), pass it verbatim; don't substitute the
     alias. Record the resolved flags in `Actually used:` (e.g. `claude:claude-opus-4-8 --effort high`).
   Do NOT use a bespoke executor agent. If a provider's flags are unverified, check its `--help`
   (or ask me) before relying on them — don't guess.
4. Each executor works ONLY in its own worktree, runs the task's `## Verify`, reports real output,
   and fills the task's `## Result` block (time, commit sha(s), verify outcome). Distinguish real
   regressions from pre-existing/environmental failures (reproduce on the untouched base branch).
5. **Publish (commit is not the finish line).** After a task verifies, push its branch and open an
   MR with a real title + description (what changed, why, kept-pinned rationale, verification,
   caveats). Opening an MR is outward-facing — **confirm with me before pushing/opening** unless I
   already said "push + MR as you go." Record the MR in the task's `## Result` and the dashboard's
   **Merge requests** table. Zero-change tasks: note "zero-change — no branch/MR", don't leave blank.
6. Keep the dashboard task-status table current, and log each meaningful action via the helper —
   `…/{{PW_HOME}}/tooling/pw-lib.sh log <slug> execute "spawned T0n (provider:model); committed <sha>; MR <url>"`.
   When all requested tasks are done: `…/{{PW_HOME}}/tooling/pw-lib.sh status <slug> review`. If
   arguments list task IDs, run only those.

Stop for my review before marking anything `accepted`. Two ways I send feedback:
- **Internal (pre-MR or general):** I add items to `task/review/T0n.review.md` and set
  `Status: verify-failed`; `/pw-review` applies them and `/pw-execute <slug> T0n` re-runs + re-verifies.
- **On the MR itself:** if I say "address the MR comments on T0n", fetch the open MR review
  threads (`glab mr diff` / `glab api …/merge_requests/<id>/discussions`, run from inside the
  repo with `GITLAB_HOST=source.golabs.io`), apply the fixes in that task's worktree, push, then
  **reply to each MR thread** summarizing the fix and **also mirror it into the internal record**
  (task `## Result` + `task/review/T0n.review.md` + a `LOG.md` line) — the project dir stays the
  source of truth even for MR-driven changes.

**A project does NOT need its MRs merged to be closeable.** MRs may sit open/on-hold for a long
time. `accepted` here means "verified + MR opened + you signed off on the change" — merging is
downstream and out of the workflow's control. See `/pw-close`.
