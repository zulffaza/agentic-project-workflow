---
name: pw-execute
description: Execute a project's PLAN.md via orchestrated worktree sub-agents
args: "--project <project-slug> [--task <T0n>]… [--wave] [--model <provider:model|agent>] [--acceptance auto] [--then-ship]"
scope: project
---

**Load shared guidance first.** Read the `pw-orchestration` skill's common rules
(`references/common.md`) before acting: authorization, operation scope, helper ownership, and
reporting. Load only the phase-specific references this operation needs. A read-only operation
must not run execution or mutation procedures.
Follow the `pw-guide-workflow` skill. Act as the ORCHESTRATOR — never edit repo code yourself.
Arguments: {{ARGS}} — the project is always `--project <slug>`; `--task <T0n>` (repeated) scopes
the run to those tasks, `--model <provider:model|agent>` overrides the model/agent for this run,
`--wave` runs only the immediately-runnable wave.

**Named-argument grammar (uniform across every /pw-* command).** The first word is the
operator; every value is a named argument. The project is always `--project <slug>`. Scalar
values are one token (quote spaces); prose values run until the next `--flag` token; a value
that starts with `--` is passed as `--flag=value`. Unknown flags and stray positional values
fail closed. Full rules: `{{PW_HOME}}/tooling/docs/conventions.md`.

Project dir: `{{PW_PROJECTS}}/<slug>`.

<!-- Pre-flight: deterministic checks before agent reasoning -->
```bash
{{PW_HOME}}/tooling/scripts/entities/pw-preflight.sh execute --project <slug> || exit 1
{{PW_HOME}}/tooling/scripts/entities/pw-doc.sh lint --kind plan --project <slug> || exit 1
{{PW_HOME}}/tooling/scripts/entities/pw-doc.sh lint --kind task --project <slug> --all || exit 1
```
**Reading the pre-flight:** `pw-preflight.sh execute` checks the PLAN `approved` sign-off, a
phase execution is legal in, and every `Execute with:` row on both axes — *permission*
(allowlist) and *availability* (`model-resolve`: the model exists in the live catalog — for
Cursor that means `agent models` PLUS `~/.cursor/cli-config.json` → `modelParameters` — and sits
inside the configured api-provider prefix scope; a row pinning a since-removed provider is a
hard stop with the re-pin candidates); the two `pw-doc.sh lint`
calls check PLAN/task-file format (tables, required fields/sections). Silent = pass; otherwise
one `pw-…:` stderr line + exit 1 — **STOP, relay it verbatim** (it names the unmet gate and the
  fix; e.g. run `/pw-review` for approval). After the gates pass, run
  `{{PW_HOME}}/tooling/scripts/entities/pw-status.sh provider-audit --project <slug>` once as a **warning**
  pass (non-blocking here): `stale-provider`/`unbound` rows name exactly what to re-pin before
  spawning. Never reason past a failed pre-flight. For an unfamiliar operator, run
  `pw-help.sh operators --name <script>` (add `--operator <op>` for a listed operator); read the
  owning group document under `{{PW_HOME}}/tooling/docs/scripts/` only when that operator's details
  matter.

1. Read `<project>/task/PLAN.md` fully. **Gate:** `…/{{PW_HOME}}/tooling/scripts/entities/pw-review-read.sh gate
   --project <slug> --file task/review/PLAN.review.md` — this is the file's CURRENT Sign-off decision only, never
   "was it ever approved"; if it exits non-zero (missing file, `in-review`, or `changes-requested`),
   STOP and ask, quoting what it printed. Checked on **every** invocation, including a resume — a
   PLAN reopened after approval (e.g. by `/pw-review`'s workflow-attributed gate transitions, when a fix lands post-approval)
   must re-block execution here even mid-run, not just on the very first call. (Per-task review
   files are **optional** — their absence never blocks execution; they only matter when a task is
   being sent back.) Then: `…/{{PW_HOME}}/tooling/scripts/entities/pw-status.sh status --project <slug> --phase executing`.
2. **Reconcile execution state before resolving scope:** run
   `{{PW_HOME}}/tooling/scripts/entities/pw-doc.sh sync --project <slug> --plan-only`.
   Task files supply Status and Result fields; the helper preserves task links, routing, and
   dependencies. If sync fails, STOP and relay the error. Never schedule from a stale PLAN table.
   **Resolve scope — this decides resume behavior, get it right:**
   - **Arguments name specific task IDs** → scope = exactly those tasks (plus an optional `"with
     <model/agent>"` override). This is the deliberate "re-verify just this one" path — run only
     what's named, then stop, whether or not other tasks in the plan are still pending.
   - **`--wave`** → scope = **only the tasks immediately runnable right now** — not yet `accepted`,
     and every entry in `depends_on` is already `done`/`accepted` at the moment you resolve scope.
     Run that wave to completion, then **stop and report** rather than cascading into whatever it
     just unblocked — the deliberate "one deployable-sized chunk, then checkpoint" path for a long
     plan, so a misbehaving orchestrator or a lost session only affects one wave's blast radius.
     Tell me which tasks are now newly ready for the *next* `--wave` call.
   - **No task IDs, no `--wave`** → this is a **resume of the whole run**, not "run one task and
     stop." Scope = **every task in the PLAN table whose `Status` is NOT YET `accepted`** — i.e.
     `todo`, `in-progress` (a stale/crashed run), or `verify-failed`. Tasks already `accepted` are
     left completely alone; tasks already `done` (committed + verified, just awaiting my review)
     are also left alone — don't re-run something that already succeeded.
   - **Keep walking the DAG to the end of *that* scope in this SAME invocation — do not stop after
     handling only one task.** The moment a task you (re)ran reaches `done`, immediately continue:
     spawn whatever depends on it *within scope*, and any other independent ready task *within
     scope*, without waiting for me to invoke `/pw-execute` again. A bare `/pw-execute --project <slug>`
     drives the run to the end of everything currently outstanding, once; `--wave` drives it only
     to the end of the immediately-runnable wave, then checkpoints.
3. Walk the dependency DAG within that scope. Spawn one executor per task, only once its
   `depends_on` are `done`/`accepted`. Parallelize independent tasks up to the plan's max. Honor
   the plan's **execution routing** and any override in the arguments; record what you used in each
   task's `Actually used:`.
   - **Route each task by its `Branch:`** — this is per-task, so a **mixed** project (fresh tasks +
     adopted branches, see the WORKFLOW "mixed projects" note) is just tasks of both kinds side by side:
     - **Fresh task** (`Branch:` is a new `agent/<slug>/<T0n>-<slug>`) → **create its worktree with
       the script** — never hand-roll `git worktree add` (branch naming, path layout and attach
       semantics live in one place: `tooling/docs/scripts/workflow-automation.md`):
       `{{PW_HOME}}/tooling/scripts/entities/pw-worktree.sh create --project <slug> --task <T0n> --repo <repo> --base <base-branch>` — it forks the
       task's `Branch:` from `origin/<base-branch>` (NOT the repo's current HEAD) at
       `worktree/<repo>/<task-id>-<slug>/` and prints the path on its last line; pass that path to
       the spawn. Two tasks in one repo may declare different bases (e.g. `master` and `spring3`) —
       fine: different `-b` args, separate branches + worktrees + MRs, parallel. If the branch
already exists the script attaches instead of dying; re-running is idempotent.
      - **Stacked task** (`Stacked on: <parent-task>` in the task file): the same `create` call forks
        the child from the parent's **exact locally verified commit** (the parent's recorded
        `verified_head`), not `origin/<base-branch>` and never a stale `origin/<parent>` ref — so a
        child starts before the parent is pushed. If the parent has no verified binding, or its
        branch head moved after verification, the script **refuses**; execute and verify the parent
        first. Verify the child against the inherited code (compare environmental failures to the
        parent snapshot, not an unrelated base), and after its `## Verify` passes, bind the verification
        so its own descendants can fork from it:
        `{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh stack-verify --project <slug> --task <T0n> --evidence <captured-verify-output>`
        (run it right after the child's `## Verify` passes; it binds the CURRENT head, the consumed
        parent commit, and the effective target, and refuses when the parent's committed code is absent
        from the child — a manual `stack-record` flag can never certify unverified work).
        If the parent changes after the child started, the child's binding is invalid — mark it stale
        (`pw-ship.sh stack-stale --project <slug> --task <T0n>`) and re-run it.
      - **Adopted task** (`Branch:` is an existing in-progress branch from `context/ADOPTED.md`) → do
       NOT create an `agent/…` branch: run the same script with the **adopted branch** as `<T0n>`'s
       task id kept, and it attaches the existing branch at the convention path — but only after
       you replace the task's `Branch:` check: the script builds `agent/<slug>/<T0n>-<slug>`, so for
       adopted branches create/attach the worktree once manually with the adopted name per
       **adopted branch**: `git -C {{PW_REPOS}}/<repo> worktree add
       {{PW_PROJECTS}}/<slug>/worktree/<repo>/<branch-slug> <existing-branch>` (no `-b`) — that is
       the single sanctioned exception to the script rule (one shared worktree per adopted branch;
       its path goes in the task's `Worktree:` field).
       **Serialize tasks that share a branch** (one worktree), but **parallelize across different
       adopted branches and all fresh tasks**. If git refuses because a branch is checked out in the
       main repo, tell me to switch that main checkout to another branch first.
4. **How to run each task** — resolve `Execute with: <provider>:<model-or-agent>` **and the
   task's optional `Route:` field** (ladder precedence: task `Route:` > PLAN `- Routing:` line >
   `PW_ROUTE_DEFAULT` > `auto`; values `auto|subagent|headless`) via the `pw-guide-workflow` skill's
   `references/execution-and-routing.md`. For a resolved cross-provider/headless route, read only
   the selected provider's headless-hook entry under `## How headless invocation actually works`
   in `{{PW_HOME}}/tooling/docs/providers.md`; read `## Effort / variant / thinking` only when the
   task declares either field. Same-provider routes do not load the provider guide. Tasks default to
   the plan's **Produced by** provider, so most
   run under the agent you're already in. **Before invoking**, re-check the resolved model on both
   axes — permission (allowlist; empty/unset = every model is allowed, the default) and
   availability (live catalog + api-provider prefix scope; catches a hand-edited task file AND a
   row pinning a provider that since left `PW_KILO_API_PROVIDERS`):
   ```bash
   {{PW_HOME}}/tooling/scripts/entities/pw-config.sh model-check  --provider <provider> --model <model-id>
   {{PW_HOME}}/tooling/scripts/entities/pw-config.sh model-resolve --provider <provider> --model <model-id>
   ```
   `model-resolve` exit 0 prints the **canonical** catalog id — that is what a headless
   `-m`/`--model` receives (gateway-nested rows bind as `kilo/alibaba-token-plan/<m>`;
   matching is exact-first — the prefix-less row names the *direct* provider line when one
   exists, gateway only as an announced fallback), never the raw row text. If either refuses, STOP that task and
   tell me — don't substitute a different model yourself or run
   it anyway. **The task file binds the model:** the resolved `Execute with:` (or the plan's
   Produced-by default) is the *only* model the spawn runs under — pass it explicitly with the
   provider's bind flag (`kilo run -m`, `claude --model`, cursor `--model`, codex `codex exec -m`). Never let the
   spawner's own session tokens (your harness's `model=`/`variant=` values) ride along — that
   silently rebinds a task away from what breakdown approved.
   - **Use the existing route and provider references; do not re-derive routing.** Follow the
     §routing ladder and selected provider hook before spawning. Same provider → native in-process
     sub-agent; different provider → supervised headless CLI. Sub-agents never cross providers.
   - **Bind only the approved task model.** Use the canonical id printed by `model-resolve`, pass
     it with that provider's bind flag, and never inherit the orchestrator's `model=`/`variant=`.
     Record the actual or degraded identity in the ledger and `Actually used:`.
   - **Preserve the spawn contract:** pass the task file as the work order; pipe prompts via stdin,
     never a long trailing argument. Log every spawn and write the same session id to `## Result →
     Session:`; resume only after `pw-session.sh session-check` reports live. Follow the ladder's
     `PW_HEADLESS_STALL`/`PW_HEADLESS_TIMEOUT` supervision rules. Unparsable output is failure;
     success requires real git artifacts and `## Verify`. Do not move to `/pw-ship` while a child
     is live. For cross-provider runs, use the selected hook entry only; use the effort table only
     when the task declares those fields. The routing ladder owns binding policy.
   - **Regression-first self-repair is opt-in** under PLAN `Results acceptance` + `AI execution
     limit` (`PW_MAX_SELF_REPAIR` defaults to 3). Repair only real regressions; environmental or
     pre-existing failures follow the `done` + caveat rule.
5. Each executor works ONLY in its own worktree, runs the task's `## Verify`, reports real output,
   and fills the task's `## Result` block (time, log path, commit sha(s), verify outcome).
   After each task starts or returns, and after each repair/re-verification changes its task file,
   run `{{PW_HOME}}/tooling/scripts/entities/pw-doc.sh sync --project <slug> --plan-only`, then
   `{{PW_HOME}}/tooling/scripts/entities/pw-doc.sh sync --project <slug> --dashboard-only`.
   STOP on sync failure. Re-read the synchronized PLAN before scheduling dependents or reporting
   completion. Never infer `accepted` from `done`.
   **`Verify outcome:` and `Notes:` are one distinct fact per (sub-)bullet, never a single run-on
   paragraph chaining several unrelated facts** (a real result + an unrelated environment hiccup +
   a mutation-test finding, say) — see `_TEMPLATE-task.md`'s own `## Result` for the exact shape.
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
6. **Optional clean-mode finish (`- Results acceptance: auto` in PLAN, or `--acceptance auto`   for this run only — default `manual` = stop at verified, exactly like before).** When the
   whole resolved scope is `done`/`accepted`: flip every task that is `done`, green on its own
   `## Verify` (self-repair rounds included), and with **zero open review/`dep-impact` items** to
   `accepted` via `pw-status.sh task-accept`, then report the clean list as an explicit result
   ("auto-accepted N; leftovers: …"). Anything not cleanly closed — exhausted self-repair, an
   open human item — stays visible/`verify-failed` as today. The PLAN gate is still checked on
   every invocation, and no `--push`/outward action happens here either way.
   - **A landed fix fans one capped §3.6 pass.** If a task this run (or right after, via
     `- Results acceptance`) repaired itself *after* a dependent already reached `done`: merge the
     fixed branch into each already-run dependent, re-run **that dependent's** `## Verify` once
     (clean → stays `done`; conflict/regression → its own flip, driver-side), and where their
     files/landing units overlap, run ≤1 `pw-reviewer`-style **dep-impact** coherence pass filing
     `dep-impact:<dep>` items into that dependent's queue — never edit another task's branch from
     this pass. Not-yet-run dependents need nothing (they already fork the fixed state).
7. **Stop at committed + verified — but only once the WHOLE resolved scope is there, or genuinely
   blocked.** `/pw-execute` does NOT push or open MRs — that's the separate, explicit `/pw-ship
   --project <slug> [--task <T0n>]…` step, so nothing goes outward until I ask. Set each task's `## Result → MR: —`
   (not shipped yet). Keep the dashboard task-status table current and log each action via the
   helper:
   `…/{{PW_HOME}}/tooling/scripts/entities/pw-status.sh log --project <slug> --actor execute --message "spawned T0n (provider:model); committed <sha>"`.
   **The dashboard `Status: review` transition is keyed to the WHOLE PLAN, not the resolved
   scope** — set it via `…/{{PW_HOME}}/tooling/scripts/entities/pw-status.sh status --project <slug> --phase review` only when *every*
   task in the *entire* `PLAN.md` table is `done`/`accepted` (or blocked only by a `verify-failed`
   dependency), regardless of whether this particular invocation was a `--wave`, a task-id-scoped
   re-run, or a full resume. A `--wave` call that finishes its wave but leaves later tasks still
   `todo` must NOT flip Status — report the wave's outcome and stop, plan still `executing`.
   Report a clean per-task summary — which reached `done`, which are still `verify-failed` and why,
   which never got a turn because their dependency is blocked, and (for `--wave`) which tasks are
   newly ready for the next `--wave` call.

Stop for my review before marking anything `accepted`. Two different re-run paths — don't confuse
them:
- **I explicitly reject one task** after review: I flip it to `Status: verify-failed` and either
  add items to `task/review/T0n.review.md` or just tell you what's wrong — `/pw-review --project <slug> --task T0n`
  applies the fix (creating the review file from my feedback if it doesn't exist), then
  `/pw-execute --project <slug> --task T0n` re-runs + re-verifies **just that task** in the same worktree, then stops.
- **A bare `/pw-execute --project <slug>` resume** (no task IDs): per step 2, this walks **everything** not
  yet `accepted` — including any task still `verify-failed` — through to the end of what's ready,
  in one invocation. It is not the same as re-running one task; don't stop early just because the
  run started from a partial/failed state.

**Completion review — only when configured.** For each task that this run brought to committed +
verified (before you summarize it), read the `task-exec` axis
(`{{PW_HOME}}/tooling/scripts/entities/pw-config.sh get --project <slug> --key review-trigger` and
`get --project <slug> --key ai-review`) and, ONLY when the trigger is `completion` and the outcome is callable (`advisory`
default; a legacy `off` row reads as advisory), run the `/pw-review ai --project <slug> --task T0n` flow for that
task — a fresh reviewer only, bounded repairs only when `review-repair task-exec=bounded` and
within `review-rounds` passes (repairs follow the normal executor ladder and re-run the task's
`## Verify`). Reviewer outage or an unverified route: one skip line per task, continue. It never
accepts a task, never pushes, and never signs off by itself (advisory) — acceptance stays mine.

**`--then-ship` (opt-in chain, never a default).** With this flag (and the PLAN gate intact +
`- Results acceptance` handling as above), when the whole resolved scope is committed + verified you
**continue straight into row 7 in the same invocation**: run `/pw-ship`'s steps — confirm the push
list with me exactly once, push each verified branch, open MRs, monitor the CI default — instead of
stopping for a second command. Ship is still its own *deliberate* step and still human-gated on the
push; the flag chains it, it doesn't skip the confirmation. Without the flag, this command stops at
verified, unchanged.

When you're ready to publish verified work (and to handle review comments left on an MR), use
`/pw-ship`. **A project does NOT need its MRs merged to be closeable** — see `/pw-close`.
