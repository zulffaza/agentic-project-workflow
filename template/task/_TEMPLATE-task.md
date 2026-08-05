# <T0n>: <short imperative title>

<!-- Self-contained: an agent handed ONLY this file must be able to do the work.
     [🤖 agent] writes this file at breakdown and fills ## Result at execution. Status is agent-
     driven (todo→in-progress→done) EXCEPT `accepted` and `verify-failed`, which are [🧑 you].
     You comment via task/review/<T0n>.review.md, not by editing this file. Legend: 🤖 · 🧑. -->

- **Repo:** <repo>            **Base branch:** <branch>
- **Branch:** `agent/<project-slug>/<T0n>-<slug>`
- **Worktree:** `worktree/<repo>/<T0n>-<slug>/`
- **depends_on:** <T-ids or none>          **Parallel group:** <Gn>
- **Status:** todo | in-progress | verify-failed | done | accepted
- **Execute with:** <provider:model-or-agent> — e.g. `claude:claude-opus-4-8` (pinned) or
  `claude:opus` (latest), `claude:sonnet`, `kilo:command_code/MiniMaxAI/MiniMax-M3`, or an existing
  agent (e.g. `code-implementation`). `provider:` maps to the CLI — see `{{PW_HOME}}/tooling/providers.md`.
  Aliases (`opus`/`sonnet`/…) track the *latest* version; **use the full name to pin** (e.g.
  `claude-opus-4-8` vs `claude-opus-5`) when reproducibility matters. Only name a `sub-agent/` def
  if no existing agent fits.
- **Effort:** <low|medium|high|xhigh|max — optional> — reasoning effort. Maps to `--effort`
  (claude) / `--variant` (kilo). Omit for the CLI default.
- **Thinking:** <on|off — optional, kilo only> — emit thinking blocks (`--thinking`).
- **Why:** <one line — why this model/agent/effort fits this task>
- **Story points:** <n> — manual-effort estimate (2 SP = 1 person-day). [🤖 set at breakdown]
- **Actually used:** <filled by the orchestrator at run time — e.g. `kilo:command_code/MiniMaxAI/MiniMax-M3 --variant high`>

> You can override the model/agent for this task when you kick off execution
> (e.g. "run this with opus"); the orchestrator records what it used in **Actually used**.

## Goal
One or two sentences: what this task changes and why.

## Context
Links to the exact inputs needed (don't make the agent read everything):
- analysis: <analysis/…#section>
- context: <context/… rows>
- code refs: `<repo>/path:line`

## Steps
1. Create the worktree:
   ```bash
   git -C {{PW_REPOS}}/<repo> worktree add \
     "{{PW_PROJECTS}}/<project-slug>/worktree/<repo>/<T0n>-<slug>" \
     -b agent/<project-slug>/<T0n>-<slug>
   ```
2. <do the change …>
3. Commit with a Conventional Commit message.

## Constraints
- Edit ONLY this worktree. Do not modify other tasks' files or repos.
- <task-specific limits>

## Verify (Definition of Done)
Runnable — the agent must run these and paste real output before reporting done.
```bash
cd {{PW_PROJECTS}}/<project-slug>/worktree/<repo>/<T0n>-<slug>
<build/test/lint command>
```
**Expected:** <e.g. "BUILD SUCCESS, 0 failures" / "tests green" / specific assertion>.

## Done means
- [ ] Change implemented on the branch above
- [ ] Verify commands run and passed (output pasted)
- [ ] Committed; branch/PR/patch produced per PLAN.md exit strategy
- [ ] Human accepted

> **If the human rejects this result:** they add items to `task/review/<T0n>.review.md` and set
> `Status: verify-failed` above. Then `/pw-review` applies the fixes and the task is re-run in its
> worktree (`/pw-execute <slug> <T0n>`) and re-verified. Same review contract as analysis/plan.

## Result (filled by the executor at run time)
- **Actually used:** <model/agent it ran with, if different from Execute with>
- **Time:** <wall-clock, e.g. 12m>
- **Commit(s):** <short-sha(s), or `zero-change` if nothing was removable>
- **MR:** <url / number, or `—` if not pushed>
- **Verify outcome:** <pass / pass-with-preexisting-failures (name them) / fail>
- **Notes:** <anything the reviewer needs — surprises, kept-pinned rationale, follow-ups>
<!-- Token/cost intentionally omitted — not measurable from inside the run. -->

