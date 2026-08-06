# <T0n>: <short imperative title>

<!-- Self-contained: an agent handed ONLY this file must be able to do the work.
     [🤖 agent] writes this file at breakdown and fills ## Result at execution. Status is agent-
     driven (todo→in-progress→done) EXCEPT `accepted` and `verify-failed`, which are [🧑 you].
     You comment via task/review/<T0n>.review.md (OPTIONAL — only if you want changes), not by
     editing this file. Legend: 🤖 · 🧑. -->

- **Repo:** <repo>            **Base branch:** <branch>
- **Branch:** `agent/<project-slug>/<T0n>-<slug>`
- **Worktree:** `worktree/<repo>/<T0n>-<slug>/`
- **depends_on:** <T-ids or none>          **Parallel group:** <Gn>
- **Status:** todo | in-progress | verify-failed | done | accepted
- **Execute with:** <provider:model-or-agent> — e.g. `claude:claude-opus-4-8` (pinned) or
  `claude:opus` (latest), `claude:sonnet`, `kilo:command_code/MiniMaxAI/MiniMax-M3`, or an existing
  agent (e.g. `code-implementation`). `provider:` maps to the CLI — see `{{PW_HOME}}/tooling/providers.md`.
  **Default to the SAME provider that ran the breakdown** (recorded in `PLAN.md` → "Produced by")
  so execution doesn't force you to switch agents — only route elsewhere when a task genuinely needs
  a stronger/cheaper/open-weight model, and say why in `Why:`.
  Aliases (`opus`/`sonnet`/…) track the *latest* version; **use the full name to pin** (e.g.
  `claude-opus-4-8` vs `claude-opus-5`) when reproducibility matters. Name the shipped `pw-executor`
  or a custom `tooling/agents/` def only if no existing agent fits.
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

## Steps  [🤖 breakdown writes these — make them DETAILED to cut executor cost]
Write steps an executor can follow **with minimal independent reasoning** — the more precise the
breakdown is here, the cheaper and more reliable the execution (a small model shouldn't have to
re-derive what to do). Each step names the **exact file**, the **exact change**, and (where it
runs code) the **exact command**. Prefer before/after snippets or literal find-replace over prose
like "update the config". If a decision is still open, it belongs in analysis/review as a `Q`, not
as a judgement call left to the executor.

<!-- ↓↓ LEVEL-OF-DETAIL EXAMPLE (aim for this granularity) ↓↓
1. Create the worktree, forking the new branch from THIS task's **Base branch** (`master` here):
   ```bash
   git -C {{PW_REPOS}}/hera fetch -q origin master
   git -C {{PW_REPOS}}/hera worktree add \
     "{{PW_PROJECTS}}/<project-slug>/worktree/hera/T01-kafka-toggle" \
     -b agent/<project-slug>/T01-kafka-toggle origin/master
   cd "{{PW_PROJECTS}}/<project-slug>/worktree/hera/T01-kafka-toggle"
   ```
2. In `src/main/resources/application.yml`, under `kafka:`, add:
   ```yaml
   kafka:
     enabled: ${KAFKA_ENABLED:false}   # NEW — feature toggle, default off
   ```
3. In `src/main/java/.../KafkaConfig.java`, annotate the `@Configuration` class with
   `@ConditionalOnProperty(name = "kafka.enabled", havingValue = "true")` (add the import
   `org.springframework.boot.autoconfigure.condition.ConditionalOnProperty`).
4. Commit: `git add -A && git commit -m "feat(kafka): gate Kafka wiring behind kafka.enabled toggle"`.
↑↑ END EXAMPLE ↑↑ -->

1. Create the worktree, forking the new branch from THIS task's **Base branch** (the `Base branch:`
   field above) — `origin/<base-branch>`, so two tasks in the same repo can target different bases
   (e.g. `master` vs `spring3`) without colliding:
   ```bash
   git -C {{PW_REPOS}}/<repo> fetch -q origin <base-branch>
   git -C {{PW_REPOS}}/<repo> worktree add \
     "{{PW_PROJECTS}}/<project-slug>/worktree/<repo>/<T0n>-<slug>" \
     -b agent/<project-slug>/<T0n>-<slug> origin/<base-branch>
   cd "{{PW_PROJECTS}}/<project-slug>/worktree/<repo>/<T0n>-<slug>"
   ```
2. <exact change #1 — file + what to change, with a snippet>
3. <exact change #2 …>
4. Commit with a Conventional Commit message.

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
- [ ] Committed (push + MR is a separate step — see `/pw-ship`)
- [ ] Human accepted

> **If the human rejects this result:** flip `Status: verify-failed` above and either (a) add items
> to `task/review/<T0n>.review.md`, or (b) just tell the agent what's wrong in chat — `/pw-review`
> will create that review file from your feedback if it doesn't exist yet. Then the task is re-run
> in its worktree (`/pw-execute <slug> <T0n>`) and re-verified. Task review is **optional**: a task
> only needs a review file when you're sending it back.

## Result (filled by the executor at run time)
- **Actually used:** <model/agent it ran with, if different from Execute with>
- **Time:** <wall-clock, e.g. 12m>
- **Log:** `worktree/<T0n>.log` <executor tees its output here so you can tail the run>
- **Commit(s):** <short-sha(s), or `zero-change` if nothing was removable>
- **MR:** <url / number, or `—` if not shipped yet (see /pw-ship)>
- **Verify outcome:** <pass / pass-with-preexisting-failures (name them) / fail>
- **Notes:** <anything the reviewer needs — surprises, kept-pinned rationale, follow-ups>
<!-- Token/cost intentionally omitted — not measurable from inside the run. -->
