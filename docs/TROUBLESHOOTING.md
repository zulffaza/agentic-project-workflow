# Troubleshooting

← [back to README](../README.md) · see also: [docs/KNOWN-ISSUES.md](./KNOWN-ISSUES.md) (verified,
dated gotchas this bundle already works around under the hood — this page is "what do I do right
now," that one is "why does this exist")

Symptom → what to do. If you don't see your symptom here, `/pw-status <slug>` (where a project
actually is) and `/pw-doctor` (whether your install is actually in sync) answer most "why isn't this
working" questions before you go digging further.

## "A `/pw-*` command isn't found / behaves like an old version"

Run `/pw-doctor` (`/pw-doctor --fix` to repair). This is almost always an install-sync issue, not a
bug in the command itself — full coverage of what it checks and when to reach for it is in
ONBOARDING.md's [Troubleshooting — `pw-doctor`](../ONBOARDING.md#troubleshooting--pw-doctor)
section; not duplicated here.

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

## "`/pw-teardown` (or `/pw-close`) skipped a worktree"

**Symptom:** `tooling/pw-teardown.sh` reports `⚠ SKIP` for a worktree instead of removing it.

**Cause:** it's a deliberate safety refusal, not a failure — the helper never removes (a) the
worktree you're currently sitting in (removing your own cwd out from under you is what once caused
an editor reload/crash), or (b) a worktree with uncommitted changes, unless you pass `--yes`.

**Fix:** `cd` out of the worktree first if that's the reason; commit or stash the changes (or
confirm you're fine discarding them and pass `--yes`) if that's the reason. Run teardown from the
bundle/project root, never from inside a worktree.

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

## "A cross-provider handoff produced no output, or the target CLI says no prompt was received"

This is a known, already-mitigated gotcha (a long inline CLI argument can vanish across a
shell-out boundary) — every headless invocation this bundle generates already pipes the prompt via
stdin to avoid it. If you're driving a CLI by hand outside this bundle's own routing and hit this,
see [docs/KNOWN-ISSUES.md](./KNOWN-ISSUES.md#a-long-inline-prompt-argument-can-silently-vanish-across-a-shell-out-boundary)
for the exact symptom and the stdin fix.

## "KiloCode's auto-approve isn't working inside a worktree"

This is a JetBrains-plugin-specific issue, not the `kilo` CLI — see
[docs/KNOWN-ISSUES.md](./KNOWN-ISSUES.md#kilocode-auto-approve-breaks-inside-git-worktrees-is-a-jetbrains-plugin-issue-not-the-cli)
for the verified cause and the workaround (drive the run from Claude Code, or approve manually;
`kilo run --auto` from the CLI itself is unaffected).

## "An MR comment I know is there isn't showing up in a fetch"

Two different, both-verified causes, depending on the shape of the comment — see
[docs/KNOWN-ISSUES.md](./KNOWN-ISSUES.md#gitlab-mr-comment-handling) for the full symptom/cause/fix
for each: a general (non-diff) comment being wrongly filtered out by `individual_note`, or GitLab's
`/discussions` endpoint lagging the raw notes table by 20+ minutes.

## "I don't know what state a project is in, or what to run next"

`/pw-status <slug>` — it's built for exactly this question (phase, dashboard `Status:`, what's
still open, what command comes next). Don't try to reconstruct it by reading `LOG.md`/`PLAN.md` by
hand first.
