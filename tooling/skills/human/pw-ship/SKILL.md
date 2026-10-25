---
name: pw-ship
description: Push verified task branches and open MRs with rich descriptions
args: "[comments | request-review | stack | draft | ready] --project <project-slug> [--task <T0n>]… [--draft] [--apply (--expect <token> | --resume <attempt-id>)] [--skip-build-check] [--resolve]"
scope: project
---

**Load shared guidance first.** Read the `pw-orchestration` skill's common rules
(`references/common.md`) before acting: authorization, operation scope, helper ownership, and
reporting. Load only the phase-specific references this operation needs. A read-only operation
must not run execution or mutation procedures.
Follow the `pw-guide-workflow` skill. Arguments: {{ARGS}}. The first word selects the mode:
`comments` = MR-comment mode (below); `request-review` = read-only request-message mode (below);
`stack` = stacked-MR surface (below); `draft` / `ready` = MR readiness (below); anything else = ship
mode (default). Every value is named: `--project <slug>` is required, and
optional task IDs scope to a subset by REPEATING `--task <T0n>` (e.g. `--task T01 --task T03`);
`--skip-build-check`
may appear in ship/comment mode; `draft`/`ready` refuse it because they never run CI. Task IDs are **optional in both
ship modes** — with none, the command applies to **every** eligible task (all shippable tasks in
ship mode; all tasks with an open MR in comment mode).

**`--resolve` is a comment-mode-only switch, and it is OFF by default.** In comment mode it lets the
run close the MR threads whose fixes it just verified (see "Handling and resolution are separate").
Without it, a comments run still fixes, verifies, pushes, replies, and records the work — it just
**leaves every thread open for your review**, so a human can check the fix against the live thread
before anything is closed. In any other mode (`ship`, `request-review`, `stack`, `draft`, `ready`) `--resolve` is a
usage error: refuse with that reason and do nothing — never push, comment, or write state. This flag
is unrelated to `pw-ship.sh resolve`, the internal operator that lists shippable candidates.

**Build-check monitoring runs by default** — after the MR is opened/updated (ship mode) or after
each fix is pushed (comment mode), this command also polls that MR's pipeline/checks to a terminal
state and reports the result; see "Build check" near the bottom for the mechanics. **This means a
plain run now waits on CI** (up to the timeout below) before it finishes, unlike before. Pass
`--skip-build-check` to opt out for this run and get the old, immediate-return behavior back.

Project dir: `{{PW_PROJECTS}}/<slug>`.

## Request-review mode (`request-review`)

**Read-only and complete on its own: when the first word is literally `request-review`, run the
procedure in `references/review-request.md`, relay its output, and STOP — this mode never pushes,
comments, polls CI, or writes project state, and it returns BEFORE the pre-flight block.** Do not treat its `--task` values as ship task
IDs and do not run the ship/comment pre-flight or the monitor machinery for it. `--resolve` is also
rejected here (it belongs to comment mode only): refuse and stop, writing nothing.

```bash
{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh request-review --project <slug> [--all | --task <T0n>]… \
  [--to <names>] [--summary] [--mr-summary] [--note] [--no-reviewers] [--prose <file>]
```

The script owns selection, MR metadata, ordering, rendering, and validation — run exactly this
and relay its stdout; never re-order or re-word the generated MR fields yourself.

**Load `references/review-request.md`** for the request-message procedure — selection, frame,
the two-call AI-prose flow (its `observed heads` comparison and editable generation prompts),
and the relay rules.

<!-- Pre-flight: deterministic checks before agent reasoning. Mode-scoped on purpose:
     PUSH needs shippable ('done') tasks; COMMENTS/SYNC need existing MR links but NOT
     'done' status (acceptance moves past done). Each gate's failure prints a
     "→ fix:" line — relay it verbatim; do not work around the gate. The task-format
     lint belongs ONLY to Ship mode step 1. -->
```bash
# Ship (push) mode:
{{PW_HOME}}/tooling/scripts/entities/pw-preflight.sh ship --project <slug> || exit 1
# Comments / sync mode (instead of the line above):
{{PW_HOME}}/tooling/scripts/entities/pw-preflight.sh comments --project <slug> || exit 1
```
**Reading the pre-flight:** `pw-preflight.sh ship` checks at least one task is actually shippable
(`done`, verified) in a legal phase; `pw-preflight.sh comments` just requires a legal phase plus at
least one task with a linked MR (nothing to comment on before the first push). Non-zero +
`pw-…:` stderr = STOP and relay it — never push against an unmet gate. After the gates pass, run
`{{PW_HOME}}/tooling/scripts/entities/pw-status.sh provider-audit --project <slug>` as a **warning** pass:
relay any `stale-provider`/`unbound`/`mismatch` row verbatim (each names a row to re-pin; the
per-spawn availability gate will hard-stop on it anyway — fix the rows first and the fan-out
never spawns a dead model). Once confirmed, the
mechanical halves are scripted:
`pw-ship.sh resolve` (candidate list), `pw-ship.sh exec` (push + MR), `pw-ship.sh mr-state-batch` /
`pw-ship.sh monitor` (state + CI waits) — how to read each:
`{{PW_HOME}}/tooling/docs/scripts/ship-and-sync.md`.

Publishing is **outward-facing** — this is the explicit "make it public" step, kept separate from
`/pw-execute` so nothing pushes until you run it. `/pw-execute` already committed + verified each
task; here we push branches and open MRs.

## Draft and readiness (`draft` / `ready`)

Shipment can create a draft MR with `--draft`; without it, creation stays non-draft. Readiness is
separate from lifecycle (`open` / `merged` / `closed`) and never changes task status, acceptance,
verification, stack state, or project phase. Draft creation keeps every normal ship gate.

```
/pw-ship draft --project <slug> --task <T0n>…                     # preview only
/pw-ship ready --project <slug> --task <T0n>…                     # preview only
/pw-ship draft --project <slug> --task <T0n>… --apply --expect <token>
/pw-ship ready --project <slug> --task <T0n>… --apply --expect <token>
/pw-ship draft --project <slug> --task <T0n>… --apply --resume <attempt-id>
```

- **Preview is the default and writes nothing.** It prints each selected MR's current readiness, the
  requested state, and a freshness token. Never apply without the human's explicit request and that
  token; never mint a token yourself.
- **Open MR only.** A missing URL, merged, closed, unreadable, or malformed MR refuses the whole
  selection before any write. A readiness change does not need the task's worktree.
- **Apply is freshness-bound.** Re-read the selection before writing; a changed title, readiness,
  lifecycle, or task-to-MR mapping rejects the apply. Run a fresh preview instead of retrying blindly.
- **Readback decides success.** Only the observed requested state on the same MR counts. A remote
  success with failed local recording is partial: report the URL and resume the recorded attempt.
- **Resume reconciles; it never widens scope.** `--apply --resume <attempt-id>` finishes an interrupted
  attempt. It skips completed MRs, confirms an already-observed change without another forge write,
  and returns an unchanged or externally changed MR for a fresh preview.
- **Existing MRs keep their readiness.** `--draft` only affects newly created MRs. Use `ready`/`draft`
  to change an existing one.
- GitLab readiness uses the title marker; GitHub uses the pull request's native draft state. Never
  infer GitHub readiness from a `Draft:` title prefix.

## Stacked MRs

**If the first word is literally `stack`, this is the stacked-MR surface (below) where `stack` previews the topology and health read-only while `stack adopt` is the import-side form that records edges only after an explicit apply confirmation**

Some tasks **inherit code** from another task in the same repository: the task file carries
`Stacked on: <parent-task>` (with PLAN's `Stacked on` column as a mirror). Its branch forked the
parent's verified commit, so its MR targets the **parent's branch**, not the ultimate base, until
the parent lands. `depends_on` stays the full prerequisite set; `Stacked on` is the one
branch-inheritance edge (a scheduling dependency alone is not a stack).

Two read-only/import operators on this command (no new user script):

- **`/pw-ship stack --project <slug>`** → `{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh stack --project <slug>` — the
  **read-only topology and health preview** (parent, effective target, branch, base, landed,
  freshness, pending operations). It writes nothing.
- **`/pw-ship stack adopt --project <slug> [--task <T0n>]…`** → the import-side operator: preview
  first (no writes), then a confirmation re-run with `--apply` (script: `pw-ship.sh stack-adopt --project <slug> [--task <T0n>]…`
  / `… --apply`). It reads each open MR's actual
  target branch and records an edge only when the target provably matches another task's branch;
  when fork boundaries or inherited commits cannot be proven it retains ambiguity and blocks
  automatic restacking. If importing would change the approved dependency graph, re-run
  `/pw-breakdown` and get PLAN re-approved before dependent execution or publication. Fresh,
  approved stacks need **no** adopt call.

```bash
{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh stack-plan --project <slug> [--task <T0n>]…   # root-first ship plan
```

- **Parent-first:** publish each MR against its **effective target** (nearest unmerged ancestor's
  branch, else the ultimate base). A parent's target branch must exist remotely at its verified
  head before a child's MR is created; `pw-ship.sh exec` refuses otherwise. An explicit child
  selection does not silently publish unpublished ancestors — show the added ancestors and get
  confirmation; if declined, report the child blocked. Never open an MR for a zero-change parent.

## Ship mode (default)
1. **Task-format gate, then candidates.** First
   `{{PW_HOME}}/tooling/scripts/entities/pw-doc.sh lint --kind task --project <slug> --all || exit 1` — push mechanics read exactly
   the fields lint checks (`Repo`/`Branch`/`## Verify`/`## Result`), so a malformed task file must
   stop the push (relay stderr; the named task needs its fields completed — usually by re-running
   `/pw-breakdown` or a small edit + `/pw-review`). Then determine which tasks are shippable —
   **run the resolver, don't re-derive it by hand**:
   ```bash
   {{PW_HOME}}/tooling/scripts/entities/pw-ship.sh resolve --project <slug>
   ```
   One line per shippable task (`done` or `accepted`): `task-id|repo|branch|base|ticket|title|has-commits|has-mr`
   (`—`/`none` where absent). `has-commits` counts the task's OWN commits on its LOCAL branch
   above its effective comparison target (a stacked child is compared against its parent, so
   inherited commits do not count). A `no` has-commits means the status lies → surface it, don't
   ship; `has-mr` set means the task is already published → it belongs to comment/sync handling,
   not here. **Skip zero-change tasks** (note "zero-change — no branch/MR" in their Result) and any
   already-shipped task (Result → MR already set). A resolve that cannot classify a candidate
   prints a `→ fix:` reason and exits non-zero with NO partial list — relay it rather than guessing
   the task's status.
   - **Adopted (continuation) project** (dashboard `Adopted:` note / `context/ADOPTED.md`): ship
     **per adopted branch**, not per task — each adopted branch is one shipment. For each, push the
     branch and, if an MR already exists (from `ADOPTED.md → MR:` or a `glab/gh` lookup on the
     branch), **update it — do NOT open a duplicate**; open a fresh MR only if there's genuinely none
     yet. With several units, that's one MR per adopted branch.
2. **Confirm before anything goes out.** List, for each shippable task: repo, branch
   (`agent/<slug>/<T0n>-<slug>`), target base branch, and the MR title (ticket prefix resolved per
   the convention below). Ask me to confirm the list. Only after I say go:
   - **Ticket-number → MR title convention:** before building the title, check `context/INDEX.md`'s
     `Source` column (ticket / URL / person) for the repo/task in question — for an adopted project,
     also check `context/ADOPTED.md` — for a ticket key (a Jira-style `PROJ-123`, or an equivalent
     issue reference). Found → prefix the title: `[<ticket-number>] <MR title>`. Nothing found →
     plain title, no brackets — **never invent or guess a placeholder ticket**. Different repos in
     the same shipment can carry different tickets — resolve **per repo/task**, not once for the
     whole project. More than one candidate ticket for the same repo/task → list every candidate in
     this confirm step and ask which one; don't pick for me.
3. For each confirmed task, from its worktree
   (`{{PW_PROJECTS}}/<slug>/worktree/<repo>/<T0n>-<slug>`):
   - Push the branch to origin.
    - Open an MR **targeting the task's effective target** (`pw-ship.sh stack` prints it): the
      **Base branch** for an independent task, or the **parent's verified-head branch** for a
      stacked task (that branch must already exist on origin; `pw-ship.sh exec` refuses otherwise),
      with a rich description (template below), title
      per the ticket convention above. **Resolve the forge + CLI per `tooling/docs/forges.md`** (host
      from this repo's own `origin` remote → `PW_FORGE_HOSTS` override, else auto-detect; an exact
      `PW_FORGE_HOSTS` entry wins) — GitLab: `glab` run from inside the worktree with
      `GITLAB_HOST=<resolved-host>`; GitHub: `gh pr create`. The script resolves the forge and
      requires the CLI **before** it pushes: a missing CLI refuses the shipment rather than pushing a
      branch with no MR path, and the forge is never switched by mere CLI availability. It also
      probes `glab mr create --help` for the `--output json` contract before the push and uses the
      plain invocation (which prints the MR URL) when the installed release lacks it. With no
      recorded MR, it first looks up an MR for the same source branch and adopts it rather than
      opening a duplicate. The recorded
      URL is verified inside `## Result` before the run reports completion.
      Never hardcode a host.
    - **If the task has a `Landing unit:` field** (a must-land-together set from PLAN's `## Landing
      units`): fill the description template's "**Landing unit:**" bullet with the unit name + the
      sibling MRs/URLs of that unit's other tasks, so reviewers review the set as one unit and don't
      mistake an interdependent MR for an independent one.
   - Record the MR in the task's `## Result → MR:` field **and** the dashboard **Merge requests**
     table (Task · Repo · MR url · Target branch · State · Build), then log it:
     `…/{{PW_HOME}}/tooling/scripts/entities/pw-status.sh log --project <slug> --actor ship --message "T0n pushed <branch>; MR <url>"`.
     The dashboard State mirrors the MR that exists: a newly created MR is `open`, while a
     continuation on an already-merged or closed MR keeps that terminal state rather than reopening it.
    - **Unless `--skip-build-check` was passed:** once the MR is open, monitor its pipeline/checks to
      a terminal state with `{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh monitor --project <slug> --task <task-id>`
      (exit 0 green — or neutral `SKIPPED`, no jobs ran, which is NOT a red build — / 1 red /
      2 still-running — it records the task file's `## Result → Build
      check:` line itself; you fill the dashboard row's `Build` column from that outcome) before
      moving to the next task. A **red**
      build → that task is **not done**: enter the build-check fix loop below (fix in the worktree,
      re-verify, push, re-monitor) until it passes or the cap is hit. If
      `--skip-build-check` was passed, leave both as `—` (not checked this run).
4. Recap: one line per task (branch → MR url → state → build result, or "skipped" if
   `--skip-build-check` was passed) — **group tasks that share a `Landing unit:`** so it's obvious
   which MRs must be reviewed/merged as a set. Remind me that **open/on-hold MRs don't block
   `/pw-close`** — `accepted` means verified + MR opened + my sign-off; merging is downstream.

### MR description template (make it genuinely useful — this is what a reviewer reads first)
```
<!-- pw-mr-summary:start -->
## What & why
<1–3 sentences: the change and the reason. Use accessible repository/ticket links, not private project-plan paths.>

## High-level changes
- <one bullet per observable behavior change a reviewer should understand — e.g. "partner sync now
  advances a CDC watermark instead of full re-scans", "the endpoint is now idempotent by cursor">

## Low-level changes
- <file or module>: <what precisely changed — function/endpoint/class names>
- …

## Verification
<the exact `## Verify` command(s) run, and the real output — "BUILD SUCCESS, 0 failures", test
counts, etc. Note any pre-existing/environmental failures and that they reproduce on the base branch.>

## Notes for the reviewer
- **Pinned/kept as-is:** <e.g. "kept lib X at 1.2 — bumping is out of scope, tracked as follow-up">
- **Risk / blast radius:** <what could break, how it's mitigated / behind a flag>
- **Follow-ups / out of scope:** <deliberately not done here>
- **What to review first:** <the 1–2 riskiest spots to eyeball>
- **Landing unit:** <only if this MR must merge as part of a set — the unit name + sibling MRs, so
  reviewers review them together and don't mistake an interdependent MR for an independent one>
- **Stacked on:** <only for a stacked task — the immediate parent MR (!n / URL), the ultimate
  destination after ancestors land, and the direct child MR(s) when known; show the root-first
  merge order, e.g. "T02 !1 → master; T03 !2 targets T02; merge order T02, T03">

<!-- pw-mr-summary:end -->
```
Keep the five headings exact and ordered. Notes for the reviewer belongs inside the summary region.
Do not create an empty Review changes section on initial shipment. `exec` verifies and stores
the marked creation body's ownership snapshot after readback; a snapshot failure is partial delivery,
even if MR creation succeeded. Preserve its source file for recovery.
For a stacked task, derive **High-level/Low-level changes** and the reviewer diff against the
**effective parent target**, not the ultimate destination (`git diff origin/<parent-branch>...<branch>`),
so the reviewer sees only this task's own changes. When a child MR URL becomes available, update the
parent MR's navigation (its description) to name the child, preserving reviewer-authored text:
append with **real line breaks** (compose the new body in a file), never literal `\n` text — the
managed summary end marker must still end a real line. Any description that carries the managed
markers is checked by `history --operation validate --file <body>` before `exec` publishes it, and
the same parser is the authority afterwards; a rejected body names the boundary to fix.
Fill every section from the task file + its `## Result` + the actual diff — don't ship a bare
"updates X" description. Derive **High-level changes** from the task's goal/intent (behavioral,
no paths — that forces real abstraction); derive **Low-level changes** by diffing the branch against
its **effective target**: the base (`git diff origin/<base>...<branch>`) for an independent task, or
the parent's target (`git diff origin/<parent-branch>...<branch>`) for a **stacked** task, so the
reviewer sees only this task's own changes. Group per file/module with real identifiers.

## MR-comment mode  (`/pw-ship comments --project <slug> [--task <T0n>]…`)

**Load `references/mr-comments.md`** and run its procedure — invocation and pending delivery,
MR-state resolution, one fixer pass per MR, reply/resolve under the `--resolve` policy above,
the recap, and the stacked cascade. Routing follows the §routing ladder in
`references/execution-and-routing.md`. The pre-flight `comments` gate above must pass first.


## Build check (on by default — `--skip-build-check` to opt out, either mode)
Runs automatically, in both modes: after the MR is opened/updated (ship mode) or after each fix is
pushed (comment mode), poll that MR's pipeline/checks until they reach a terminal state, using the
**Build/CI status invocation** column in `tooling/docs/forges.md`'s Registry (same per-repo forge
resolution as everything else here — never hardcode a host or a CLI). Pass `--skip-build-check` to
skip this entirely for the run and get the old immediate-return behavior (dashboard/`## Result`
`Build`/`Build check` fields stay `—`, recap says "skipped"). **A red build means that task is NOT
done** — it is not shipped until the pipeline passes; see the fix loop below.
- **Terminal states:** GitHub `SUCCESS`/`FAILURE`/`CANCELLED` (via `gh pr checks`); GitLab
  `success`/`failed`/`canceled` (via the pipeline's `.status`). Anything else
  (`pending`/`running`/`created`) means keep polling. A **`skipped`** pipeline is terminal-**neutral**
  (exit 0, "no CI jobs ran for this push" — repo pipeline rules), NOT a red build: never enter the
  fix loop on it, and say so in the recap. The monitor selects the MR **head sha's** pipelines —
  a skipped branch pipeline or a stale previous-push pipeline can't masquerade as the result.
- **Timeout, not an infinite wait:** poll on a short interval (~30s) up to a ~15 minute budget. Still
  not terminal at the budget → report it as **"still running — not yet resolved"** in the recap and
  the `## Result → Build check:` field (`UNRESOLVED (timeout …)`), rather than blocking the rest of
  the run on it — a previous `SUCCESS` must not keep describing the latest run.
- **Build-check fix loop (a red build → the task is NOT done → keep fixing until green):**
  1. **Diagnose** — read the failing job's output (GitLab: `glab api projects/:id/pipelines/<id>/jobs`
     → the failed job's trace; GitHub: the failing check's details via `gh api`). Bounded: you need
     the failing test/compile error, not the whole log.
  2. **Attribution check** — if the failure reproduces on the untouched base branch, or is clearly
     unrelated/environmental (a job that also fails on `main`, flaky infra), do **not** churn:
     report it as "build failed — unrelated/environmental, not caused by this task" and stop the
     loop (the task is still not done until a human decides). Only fix failures your change caused.
  3. **Fix + push** — edit the task's worktree, re-run its `## Verify` locally, commit, and push to
     the same branch (the MR updates in place; no new MR, no re-confirmation — the shipment was
     already confirmed). Then re-monitor the pipeline.
  4. **Repeat until green.** Cap: **at most 3 fix rounds per task per run.** Hitting the cap still
     red → stop, report the remaining error in the recap and the task's `## Result`, and tell me the
     task is NOT done — ask whether to keep fixing or take another action. Never claim `done` on a
     failing build.

## Ship-surface review (only when configured)

After a run whose shipped tasks finished with a green build check (or a reported
unresolved/environmental one), read the `ship` axis
(`{{PW_HOME}}/tooling/scripts/entities/pw-config.sh get --project <slug> --key review-trigger` and
`get --project <slug> --key ai-review`) and, ONLY when the trigger is `completion` and the outcome is callable (`advisory`
default; a legacy `off` row reads as advisory), run `/pw-review ai --project <slug> --task T0n` for each shipped
task — a fresh reviewer only (it reads the task's committed diff + MR description; the item record
stays in `task/review/T0n.review.md`). Bounded repairs only when `review-repair ship=bounded`
within `review-rounds` passes; repairs go through the executor ladder, re-run the task's
`## Verify`, push to the same branch, and re-monitor the pipeline before any fresh pass. The
reviewer never writes forge comments (that is the comments flow above), never re-confirms pushes,
and never merges. Outage or an unverified route: one skip line, continue. Advisory findings with a
green build do not block the ship — they are mine to disposition.
