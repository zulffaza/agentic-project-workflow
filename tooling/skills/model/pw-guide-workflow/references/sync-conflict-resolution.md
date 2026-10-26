# Sync conflict resolution (opt-in)

Load this reference only when `/pw-sync` runs with `--auto-resolve`, or when it resumes a recorded
sync attempt. An ordinary sync keeps the default conflict abort and does not read this file.

The flag authorizes one reconciliation attempt for this invocation. It does not authorize a force
push, history rewrite, squash/rebase restack, MR merge, thread resolution, or a second repair
budget. Unclear intent still stops for a human decision.

## Delegated worker

`/pw-sync --auto-resolve` may hand this one conflicted branch to `pw-sync-conflict-fixer` (executor
lane, task pin) with a bounded work order. The driver owns scheduling and the attempt; the worker owns
resolution, verification, publication and CI observation for that head. Clean merges spawn no worker.
A descendant waits for its parent's verified head before its own conflict work becomes ready.
Delegation does not add a repair allowance or authorize force-push, restack, MR merge or thread work.

## Inputs and attempt state

`pw-ship.sh sync-attempt` records one attempt per task in `task/sync-attempts.tsv`. Use it; never
hand-edit the file.

```text
S={{PW_HOME}}/tooling/scripts/entities/pw-ship.sh
$S sync-attempt begin --project <slug> --task <T0n> --kind <independent|stack> --mode auto --target-branch <effective-target-branch>
$S sync-attempt show --project <slug> --task <T0n>
$S sync-attempt check --project <slug> --task <T0n>
```

`begin` pins the local start HEAD, `origin/<task-branch>`, the effective target branch, and its
`origin/<target-branch>` SHA. Fetch before `begin`; a missing origin ref is a blocker, not a reason
to resolve against a branch name.

`check` is a pre-publication freshness gate. It compares the live fetched refs and the worktree
HEAD with the pinned tuple. Exit 0 prints `fresh`; exit 1 prints `stale:` and a reason. On stale,
stop: do not resolve or push against moved inputs. Re-capture a new attempt only after the caller
confirms the new target, and never relabel the same unresolved work to obtain another repair pass.

Before publishing, also re-observe the MR: it must remain open and keep the recorded repository,
source branch, and target branch. Missing refs, forge errors, and unknown state are blockers.

## Resolve the conflict

1. **Merge through the guarded operator, not raw `git merge`.**

   ```text
   $S sync-merge --project <slug> --task <T0n> --target <pinned-target-sha> --keep-conflict
   ```

   Exit 0 means a clean merge (or already contained) was recorded at stage `resolved`.
   Exit 2 means the merge failed operationally or the default abort path ran; treat the attempt as
   failed and continue with unrelated tasks. Exit 3 means the conflict is intentionally left in the
   worktree for this procedure.

2. **Inspect before editing.** Read the merge base, both index sides, the conflicted paths, the task
   brief, the repository guidance, and the verification instructions. Use task history only as
   needed. Classify real unmerged paths; a nonzero merge exit alone is not proof of a content
   conflict.

3. **Reconcile by intent, preserving both sides.** For each path, explain how the result preserves
   the task's intended behavior and the incoming target change. Edit conflicted files, then make only
   compatibility edits required to integrate both existing changes.
   - **Never resolve a path by choosing one side as a whole.** Do not use `git checkout --ours`,
     `git checkout --theirs`, "accept current", or "accept incoming" on a conflicted file. Keep every
     change from both sides unless the owner says one is obsolete.
   - Root cause, not symptom: follow callers and shared helpers when the conflict reveals a shared
     contract change.
   - Do not drop incoming functionality or weaken/delete checks to get green output.
   - Respect generated files: regenerate with the repository's prescribed tool.
   - Stop on binary, submodule, generated-file, or semantic conflicts without reliable evidence.

   **Additive-list example.** A changelog file gains one column on each side:

   ```yaml
   # merge base
   columns:
     - common

   # task branch adds
     - server_key

   # target adds
     - auth_header_value

   # correct resolution keeps both additions
   columns:
     - common
     - server_key
     - auth_header_value
   ```

   Follow the file's existing order. If both sides impose incompatible ordering or change the same
   key to different values, stop and ask; do not choose.

   **Two-sided audit before finishing.** For every conflicted path, compare the merge base, the task
   side, and the target side. List each side's intended change, then confirm the staged result
   contains it. `sync-merge` records the three blob ids; `sync-finish` uses them to refuse a result
   that is byte-identical to one side while both sides changed the path. That refusal is a warning
   that work was dropped, not an obstacle to bypass.

   **When both intents cannot coexist**, stop and ask the owner. Present the path, the relevant base
   / task / target snippets, the candidate resolutions, and one question about which behavior wins.
   Do not pass `--allow-one-sided` on your own initiative. Use it only after the owner confirms that
   one side is obsolete, pass `--owner-approved`, and record the reason.

4. **Validate and complete the merge deterministically.**

   ```text
   $S sync-finish --project <slug> --task <T0n>
   ```

   `sync-finish` requires an active attempt-owned merge, no unmerged paths, and no introduced
   conflict markers in the staged diff. It compares each staged path with the recorded base/task/
   target blobs, refuses a one-sided result, and refuses a result that drops a line either side
   added. It completes the merge with its original parents and records `resolved` at the result
   HEAD. Do not amend or rewrite the task's earlier commits.

   If the owner decided one side is obsolete, pass the exact path and reason:

   ```text
   $S sync-finish --project <slug> --task <T0n> --allow-one-sided <path> --reason "<why the other side is obsolete>" --owner-approved
   ```

   The reason is written to `task/.sync-evidence/<task>-resolution.md`. It is audit evidence, not a
   substitute for the owner's decision.

5. **Write the attempt's rationale** where the project records decisions: what each side intended,
   why the resolution is compatible, and any scope limit. Keep it short and behavior-focused.

## Verify and publish

Run the task's complete `## Verify` block and any integration check the conflict suggests. Capture
the real output; never report a check you did not run.

```text
$S sync-bind --project <slug> --task <T0n> --evidence <captured-output-file>
```

`sync-bind` requires a clean worktree and a HEAD equal to the recorded result HEAD. If verification
fails because of the resolution, inspect and commit one allowed repair, verify that new HEAD, and
bind it again; `sync-bind` records the repair once. A second differing HEAD is refused, so the cap
survives a resumed session or a new worker.

At most **one** follow-up repair pass is allowed for a regression caused by this resolution,
followed by complete re-verification. It consumes the shared persistent code-repair budget for
`<task>@<branch>` (`repair-round`); if that budget is exhausted, the sync repair is refused. The
attempt's own counter prevents a second sync repair even when the shared budget has room. An
environment blocker is not a code regression and never consumes a round or counts as a passing
check.

For a stacked task, rebind the stack tuple before any descendant advances:

```text
$S stack-verify --project <slug> --task <T0n> --evidence <captured-output-file> --head <final-head> --ci-sha pending --ci-target <effective-target>
```

Then integrate each affected descendant from its immediate parent's verified head, run that
descendant's own Verify, bind its tuple, and record a true inherited update
(`stack-inherited --parent <parent> --parent-sha <verified-parent-sha>`). Do not fabricate review
comments or resolve threads for inherited changes. Keep a shipped descendant's `describe` stage
pending until its required description delivery lands. Never clear operation debt to force a retry.

Publish with a plain push only after `sync-bind` (and stack binding, if applicable) succeeds:

```text
$S sync-attempt set --project <slug> --task <T0n> --stage pushed
```

A rejected push stays rejected; never switch to force. Then run the normal `monitor` call and
report its actual disposition. A pre-push `pending` CI marker is not CI success.

## Recovery

- **Interrupted before the merge commit:** `sync-attempt show` reports `prepared` or `conflict` and
  `check` tells you whether inputs or HEAD moved. Revalidate before continuing. Do not blindly
  restart.
- **Active attempt-owned merge:** match the worktree, branch, merge parents, and captured SHAs
  before editing or finishing. If ownership is unclear, stop.
- **Committed local merge:** inspect the recorded result HEAD; reuse verification only for that
  exact HEAD and input context.
- **Unknown push outcome:** observe the remote branch and MR before retrying. A timeout does not
  prove the push failed.
- **Publication observed, local record missing:** reconcile the record and CI evidence without
  replaying the merge.
- **Abort:** `$S sync-abort --project <slug> --task <T0n>`. It aborts only an active merge and
  reports untracked files. Remove only files proven to belong to this attempt; preserve patches and
  stop when ownership is unclear. Never use broad cleanup or hard reset.

A resumed invocation without `--auto-resolve` may inspect pending state but must not start or
continue agent conflict edits. Publication still requires confirmation covering the recovered
attempt; a local record is not approval.

## Stop conditions

Stop and report, without choosing a business rule, when:

- intent is ambiguous (API shape, data semantics, ownership, or policy);
- the target or remote task head moved, or the MR closed/retargeted;
- an unsupported conflict type appears (binary, submodule, generated file without an authoritative
  regenerator, rename/delete with unclear ownership);
- the repair allowance is exhausted or verification is unavailable;
- the worktree is dirty, has an unrelated operation, or fails ownership checks.

Report the mode, starting/target/result SHAs, resolved paths, rationale, verification output,
repair count, publication, and CI disposition. Use the existing Result and status-log conventions.
