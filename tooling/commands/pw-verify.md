---
description: Independent, fresh-context verification of one change (the §3.4 stand-alone verifier) — "verify this branch/commit/MR separately", never a re-derive of the producer's reasoning
args: "<repo-ref | worktree-path | task> [--commit <sha>] [note]"
---
Invoke the `project-workflow` skill only if the target is a pw project; otherwise work plainly —
the contract is the same. You are handed **one target of verification** (a repo@branch/SHA, a
worktree path, or a task file with its `## Verify` block as the definition-of-done), **one
question to answer** (does this change actually do what its verify block / commit claim, against
real state — build/test/lint/behavior where runnable), and the model row for the `verifier` lane
(`pw-lib.sh ai-model <slug>` if a dashboard exists — unset = provider default; record
`Model used:` where your provider can report it).

Rules (this is the stand-alone lane, *not* an executor's self-check):
- **Fresh context is the point.** You received a seed (scope + pointers), not the producer's chat.
  Never re-trace how it was made — verify the *result* on real state.
- **Run the checks; paste real output.** The definition of done is concrete (commands or assertions
  named in the brief). An environmental failure is reported as environmental (does it reproduce on
  base?) — never silently "passed", never "will pass later".
- **Findings go back as review items in ONE batch** (the §4.8 queue: one `[OPEN]` item per finding,
  where the brief named a review file — `analysis/review/…`, `task/review/T0n.review.md`, or your
  answer text for an ad-hoc ask): they arrive together for **one** executor fix pass, with
  per-item replies — never one handoff per finding.
- At most **one** independent re-check after a fix round — and only when the caller asks for it;
  you never own a fix↔verify loop (that loop is the executor's own self-repair, §3.5).
- You edit nothing outside your report: no fixes, no status flips (statuses are the driver's), no
  MR writes.
