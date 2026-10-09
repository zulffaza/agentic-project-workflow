# Troubleshooting

← [back to README](../README.md)

Symptom → what to do. If you don't see your symptom here, `/pw-status <slug>` (where a project
actually is) and `/pw-doctor` (whether your install is actually in sync) answer most "why isn't
this working" questions before you go digging further. Every entry below is self-contained: the
action, plus the one-line cause where knowing it helps.

## Start with the symptom

| What you see | First action |
|---|---|
| Unsure what to run next | `/pw-help project <slug>` |
| Command missing or stale | `/pw-doctor`; if unavailable, follow [setup recovery](../ONBOARDING.md#troubleshooting--pw-doctor) |
| Execution stopped or session ended | `/pw-status <slug>`, then resume the appropriate task scope |
| Approval blocks the next step | Read the named review file, apply feedback, and explicitly sign off after review |
| Model unavailable or project records disagree | `/pw-doctor --project <slug>` and `/pw-config <slug> show` |

Read the detailed symptom below for the cause and recovery action.
`--fix` repairs supported deterministic findings. It does not supply approval or settle project decisions.

## "A `/pw-*` command isn't found / behaves like an old version"

If `/pw-doctor` is available, run it and use `/pw-doctor --fix` for supported installation drift.
If all workflow commands are missing, use a terminal:

1. Open the bundle's `pw.config.sh` and confirm that `PW_PROVIDERS` includes your CLI.
2. Run `./bootstrap.sh` and check that it detects the enabled CLI.
3. Return to the agent session and check `/pw-help`.

See [setup](../ONBOARDING.md#setup-in-4-steps) for provider names and [installation recovery](../ONBOARDING.md#troubleshooting--pw-doctor) for drift.

## "git refuses to create a worktree — branch is already checked out"

**Symptom:** `/pw-execute` (or you, by hand) hits `fatal: '<branch>' is already checked out at
'<path>'` when creating a worktree for an **adopted** branch (fresh `agent/…` branches never hit
this — each gets a brand-new branch name).

**Cause:** a branch can only be checked out in one worktree (or the main repo checkout) at a time.
An adopted branch is often also checked out in your own day-to-day clone of that repo.

**Fix:** switch the main repo's checkout to something else first —
```bash
git -C $PW_REPOS/<repo> switch <some-other-branch>   # or: git -C $PW_REPOS/<repo> switch --detach
```
then re-run `/pw-execute`. This is spelled out in-line in `/pw-execute`'s own routing step for
exactly this reason — it's not a bug, just a git-worktree invariant.

## "A task has been stuck `in-progress` for a while" (crashed/interrupted run)

**Symptom:** `task/PLAN.md`'s status table still shows a task as `in-progress`, but nothing is
actually running — the orchestrator session that started it was killed, crashed, or you closed it.

**Fix:** just re-run `/pw-execute <slug>` (or `/pw-execute <slug> <task-id>` for just that one).
Step 2 of `/pw-execute` explicitly treats `in-progress` as a stale/crashed run and re-runs it as
part of a normal resume — you do **not** need to hand-edit the status back to `todo` first. If the
task's worktree already has partial/uncommitted changes from the crashed attempt, the re-run
happens in that same worktree (nothing is thrown away silently) — check `git -C
<worktree-path> status` yourself first if you want to see what's there before it continues.

## "`/pw-close` skipped a worktree"

**Symptom:** the worktree teardown step reports `⚠ SKIP` for a worktree instead of removing it.

Close skips a worktree when you are inside it or it contains uncommitted changes.

- If it is your current directory, move to the bundle or project root. Close terminals or editor tabs tied to that worktree.
- If it is dirty, inspect the changes and commit or stash the work you need.
- Re-run `/pw-close <slug>` from outside the worktree.

If you want to discard dirty work, tell the agent explicitly. It must confirm before removing that worktree.

## "`/pw-execute` (or `/pw-breakdown`) refused a model — allowlist"

**Symptom:** a task's chosen model/agent is rejected with something like "not in allowlist" instead
of running.

**Cause:** you've set `PW_MODEL_ALLOWLIST_CLAUDE`/`_KILO`/`_OPENCODE` in `pw.config.sh` as a cost
guard, and the chosen model doesn't match any of its glob patterns. This is intentional —
**empty/unset allows every model**, so if you're seeing this at all, an allowlist is configured.

**Fix:** either pick a model that matches an existing pattern, or widen the pattern in
`pw.config.sh` if the refusal was a false restriction. Don't hand-edit the task file to bypass the
check — `/pw-execute` re-checks right before invoking specifically to catch that. Run `/pw-doctor`
to see, per configured pattern, how many real models in your live catalog it actually matches (a
zero-match pattern is usually a typo or a stale model id) — full detail in
[docs/EXECUTION.md](./EXECUTION.md#model-allowlist-optional--a-cost-guard-not-a-routing-mechanism).

## "`/pw-execute` refused a row — model/provider *not available* (not the allowlist)"

**Symptom:** the execute pre-flight (or a spawn-time check) stops with a `model-resolve` refusal —
"not in the live catalog" or "OUTSIDE the PW_..._API_PROVIDERS scope" — even though no allowlist is
configured.

**Cause:** this is the *availability* axis, separate from the allowlist's *permission* axis: the row
pins a model that doesn't exist right now, or a provider/api-provider that left your
`pw.config.sh` since the row was written (a mid-project provider migration — subs ended, BYOK
removed, auth dropped). The pipeline refuses instead of launching a detached run that would fail
mid-flight.

Inspect the current settings and all affected rows:

```text
/pw-config <slug> show
/pw-doctor --project <slug>
```

Choose a real, in-scope model from the reported candidates, then update the pin:

```text
/pw-config <slug> set pin T02=<provider>:<model-id>
```

Use the affected task ID. This updates both the task and its PLAN row.
Alternatively, restore the intended provider/backend in `pw.config.sh` and recheck availability.
See [model catalog lookup](EXECUTION.md#check-the-model-catalog-before-pinning).

## "A headless run is stuck / a task flipped `verify-failed (headless-stall)`"

**Symptom:** a detached executor stops producing output; after a while the child is killed and the
task shows `verify-failed` with a `headless-stall` note in the ledger.

**Cause:** supervision working as designed — a child whose log hasn't grown for the configured
stall budget (or that blew its timeout) is killed rather than left wedged (an auth prompt with no
TTY, a network wedge, a model that stopped responding).

**Fix:** read `worktree/<T0n>.log` (its tail shows where it stalled), then re-run the task — the
next pass is a **seed-patched re-spawn**, not a resume of the killed id. Budgets are
`PW_HEADLESS_STALL` / `PW_HEADLESS_TIMEOUT` in `pw.config.sh`.

## "A cross-provider handoff produced no output, or the target CLI says no prompt was received"

This is a known, already-mitigated gotcha (a long inline CLI argument can vanish across a
shell-out boundary) — every headless invocation this bundle generates already pipes the prompt via
stdin to avoid it. If you're driving a CLI by hand outside this bundle's own routing and hit this,
the fix is the same: pipe the prompt via stdin (`printf '%s' "$PROMPT" | <cli> …`) instead of
passing it as a trailing argument — stdin is immune.

## "KiloCode's auto-approve isn't working inside a worktree"

This is a JetBrains-plugin-specific issue, not the `kilo` CLI — verified: a headless `kilo run`
creates worktrees, writes, and commits inside them without issue. The workaround is to drive the
run from Claude Code, or approve manually (`kilo run --auto` from the CLI itself is unaffected).

## "An MR comment I know is there isn't showing up in a fetch"

Two verified causes, depending on the shape of the comment: a general (non-diff) comment being
wrongly filtered out by GitLab's `individual_note` field (it means "single comment vs threaded
chain" — a *different axis* from diff-anchored, so a real resolvable follow-up can carry
`individual_note: false`; this bundle classifies strictly by system/resolvable/resolved instead),
and — historically — GitLab's `/discussions` endpoint lagging the raw notes table by 20+ minutes,
which is why this bundle reads `/notes` as the primary source. If a hand-rolled fetch outside
this bundle misses a comment, check both: don't filter on `individual_note`, and query `/notes`
rather than `/discussions`.

## "Changes were pushed, but the MR description update is pending"

Push, replies, verification, and description delivery have separate outcomes.
Read the recap to identify which step failed.

| Reported outcome | What to do |
|---|---|
| `description update pending` | Read the delivery error; the description did not verify after the write |
| `summary refresh pending` | Resolve the reported ownership or newer-head conflict before retrying |
| GitLab returns HTTP 415 during description delivery | Update the workflow bundle; older versions can send a description write without the required JSON content type |

After updating the bundle, run `/pw-doctor` and repair reported installation drift with `/pw-doctor --fix`.
To retry a pending review-attempt delivery, use the affected task ID:

```text
/pw-ship <slug> T02 comments
```

The retry reuses the saved attempt block and its original order. It also processes any new actionable comments.
Inspect the recap for successful description delivery; a successful push alone does not confirm it.
See [description and review-attempt history](REVIEW.md#description-and-review-attempt-history).

## "The review-request message looks wrong, or the frame file is missing"

`/pw-ship <slug> request-review` renders its message through one editable frame file:
`user-templates/review-request.md` inside your workflow install, unless you point
`PW_REVIEW_REQUEST_TEMPLATE_FILE` at a different file (a relative path resolves under the install
root). The frame must keep each of `{{TO_BLOCK}}`, `{{SUMMARY_BLOCK}}`, `{{MR_BLOCKS}}`,
`{{NOTE_BLOCK}}` exactly once; `{{PROJECT}}` is optional.

| Symptom | What to do |
|---|---|
| "review-frame template missing" (default path) | The install predates the frame or the file was deleted — run `/pw-doctor --fix` to seed it again |
| "configured review-frame template missing" | The path in `PW_REVIEW_REQUEST_TEMPLATE_FILE` is wrong or the file is gone — create it or correct the setting in `pw.config.sh`; a custom path is never auto-created |
| "template invalid … exactly once" | Edit the frame file: keep each block placeholder exactly once (order is yours) and remove unknown `{{…}}` tokens; your own static text is fine and never overwritten |
| Message text is fine but you want different wording | Edit the frame file — the frame is the whole outer message, and it is read fresh on every run |

Nothing else is configurable inside the message: per-MR fields and summaries use built-in formats.
Run `/pw-config global show` to see the effective frame path and whether it is the default or a
custom setting. The frame is plain Markdown and is never executed — but only you should edit it
(and the same care applies as with any file an agent reads).

## "A stacked task won't start, ship, or close"

A **stacked** task (one whose task file carries `Stacked on:`) inherits another task's code, so its
start, ship, and close depend on that parent:

- **Won't start:** the parent has no verified commit yet, or its branch moved after verification.
  Run and verify the parent first, then start the child. Starting a child never pushes the parent.
- **Won't ship:** a stacked child's MR targets the parent's branch, so the parent's branch must be
  published first — ship the parent, then the child. Merge order is parent, then child.
- **Won't close / shows "stale":** an upstream parent changed after the child was verified (or a
  stack update is still in progress). Run `/pw-sync <slug> <child>` to merge the updated parent,
  re-verify, and push — that clears the debt. A squash/rebase parent landing keeps the child
  promotion blocked on purpose until you approve an explicit restack; a blind rebase can lose work.
  A not-yet-started stacked child shows **unverified** (not stale): it does not block shipping its
  parent, but it must bind before its own ship — a done or accepted task without that binding still
  blocks.
- **"Published but the local mirror is pending" after a retarget:** the forge is already correct;
  re-run the retarget with `--apply` to finish the local state and dashboard. It resumes the pending
  recovery row and does **not** write to the forge again. Never delete a pending recovery row by
  hand; `stack-debt` blocks shipping until it resolves.
- **Preview anything first:** `/pw-ship <slug> stack` shows the parents, targets, freshness, and any
  pending update without changing a thing. `/pw-doctor --project <slug>` reports stack topology and
  PLAN/field mismatches (and `--fix` re-syncs the PLAN `Stacked on` cell).

## "I don't know what state a project is in, or what to run next"

`/pw-status <slug>` — it's built for exactly this question (phase, dashboard `Status:`, what's
still open, what command comes next). Don't try to reconstruct it by reading `LOG.md`/`PLAN.md` by
hand first.

## "I want every consistency question about one project answered at once"

`/pw-doctor --project <slug>` — the project side of the doctor: doc format, template currency,
PLAN/RFC/MR agreement, and every config line checked against your **current** `pw.config.sh` (so a
provider you dropped mid-project surfaces as `✗`, not a surprise at spawn time). `✗` lines carry
their fix command; add `--fix` and it applies only the repairs that have a deterministic writer
(e.g. inserting a missing `AI Review:` line with explicit `off` values — older projects started
before that line was mandatory self-heal here). Exit non-zero on any `✗`, so you can gate CI on it.
This never replaces `/pw-status` (report) or the phase gates themselves — it *reuses* them.

## "My project still tells me to run internal scripts after an update"

The installed commands and the guidance copied into a project are separate.
`/pw-doctor --fix` refreshes the installed workflow. Existing project prose needs a project-scoped preview:

```text
/pw-doctor --project <slug> --guidance
```

Inspect the proposed replacements, then request application to that project:

```text
/pw-doctor --project <slug> --guidance --apply
/pw-doctor --project <slug> --guidance
```

The final preview must show zero remaining recognized replacements. Customized text can remain skipped.

Legacy instructions inside analysis and task review files are included, such as review creation, automatic contents refresh, archiving, and phase reopening.
A skipped review file can already be current or contain wording that does not match a recognized rule.
If it still gives outdated instructions, compare them with the [review guide](REVIEW.md) and [rewind recipe](RECIPES.md#recover-or-reopen-a-phase).
Guidance repair does not rewrite custom wording or execute the review actions described in those instructions.
This mode repairs known workflow-authored guidance, while preserving review history, provenance, MR records, stack state, and project phase.
It does not run project health checks or publish changes.
Use health doctor separately for consistency findings. Do not combine `--guidance` with `--fix`.
See the [guidance recipe](RECIPES.md#refresh-old-project-guidance-after-a-workflow-update) for scope and expected output.
