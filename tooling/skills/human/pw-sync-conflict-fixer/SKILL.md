---
name: pw-sync-conflict-fixer
args: "--work-order <path-or-inline-json>   (worker-only: supplied by /pw-sync --auto-resolve)"
scope: project
description: Resolve ONE attempt-owned /pw-sync merge conflict end to end — confirm the pinned attempt, reconcile both intents, finish the guarded merge, verify, push, observe CI, and return terminal evidence within the single-repair allowance. Invoked by the /pw-sync driver under --auto-resolve; never a public command.
---

# pw-sync-conflict-fixer

**Load shared guidance first.** Read the `pw-orchestration` skill's common rules
(`references/common.md`) before acting: authorization, operation scope, helper ownership, and
reporting. Load only the phase-specific references this operation needs.

This is a **worker-only command**: the `/pw-sync` driver invokes it under `--auto-resolve`.
You are the **sync conflict fixer** for one bounded work order. Never run it as a standalone sync. The driver already classified a real
merge conflict (`sync-merge` exit 3) and owns scheduling. This skill never starts a sync sweep,
never re-runs the merge, and never treats loading it as authorization.

Read `{{PW_HOME}}/tooling/skills/model/pw-guide-workflow/references/sync-conflict-resolution.md`
and follow it. That reference owns the resolution mechanics; this skill fixes the unit of work and its
completion contract.

## Work order you must receive

- Invocation/attempt id, project, task, repository, branch, owned worktree, effective target branch.
- Pinned start/task/target SHAs and the recorded conflict manifest.
- Execution pin and model/tuning binding; exclusive ownership.
- Authorization: plain push allowed, owner decisions already obtained, CI policy.
- Repair receipt and remaining allowance; prior publication/reconciliation state.

Refuse to edit when the worktree/branch/HEAD, Merge parents, or target do not match the attempt, when
inputs moved, or when the MR is no longer open with the recorded repository/branch/target.

## Required lifecycle

1. **Confirm.** Verify the attempt-owned merge, conflict manifest, and both sides before editing.
2. **Reconcile by intent.** Preserve both sides; never choose one side wholesale; never use
   `--ours`/`--theirs` shortcuts. Regenerate generated files with the prescribed tool. Stop on
   ambiguous intent, binaries/submodules, or an unsupported conflict type.
3. **Finish deterministically.** Use `sync-finish` (and its one-sided guard only with an explicit owner
   decision). Keep the recorded parents; do not amend earlier commits.
4. **Verify.** Run the complete `## Verify` block on the resulting head, capture real output, and bind it
   with `sync-bind`. For a stacked task, rebind the stack tuple before any descendant advances.
5. **Publish.** Plain push only under the confirmed scope; never force. Reconcile an unknown push
   outcome remotely before retrying.
6. **Observe CI.** Monitor the new head/target context to a terminal state; pending is not success.
   Report red/pending/skipped honestly and do not undo a published sync.
7. **Repair once.** The attempt allows at most **one** resolution-caused follow-up repair, spending the
   shared budget. Delegation does not add a second allowance.

## Completion evidence

Return start/target/result/published SHAs, per-path two-sided rationale, verification output, repair
usage, CI identifiers/disposition, attempt stages, publication/readback, pending decisions, and
remaining stack debt. Never accept tasks, hand-edit dashboards, merge MRs, or touch comment threads.

End with `Model used: <provider:model>`.
