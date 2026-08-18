# Review feedback (per-artifact `.review.md`, in a `review/` subdir)

Human feedback on any doc lives in a review file under a **`review/` subdir** beside it, NOT inline
(you rewrite the doc when applying fixes and would clobber the notes):
`analysis/x.md`→`analysis/review/x.review.md`, `task/PLAN.md`→`task/review/PLAN.review.md`,
`task/T0n.md`→`task/review/T0n.review.md` (from `agentic-project-workflow/template/_REVIEW.template.md`).
Rules you MUST follow:

- **`/pw-review` is scoped to the current phase** (resolved from the dashboard `Status:`), not the
  whole project — process only that phase's `review/` dir, don't open every `.review.md`.
- **`/pw-review` NEVER changes the dashboard `Status:`** — reviewing is not a phase transition.
- **Task review is OPTIONAL.** Only the PLAN sign-off gates execution; per-task `T0n.review.md`
  files exist whenever the human wants to send *any* feedback on a task — either **before**
  execution (critiquing the planned steps) or **after** (rejecting a result). If a task is flipped
  to `verify-failed` but has **no** review file, create it from `_REVIEW.template.md` using the
  human's chat feedback, then apply it — don't silently do nothing (a frequent confusion). If
  there's no feedback anywhere, ask.
- Before editing any doc, read its `.review.md` first.
- Apply each `🔴 open` item, append a `↳ agent:` reply, flip it to `🟢 resolved`. **Never edit or
  delete the human's comment text** — it's the source of truth for what was asked.
- **Fixing `analysis/<topic>.md` specifically:** rewrite its §1–4 prose cleanly in place — never
  append, never leave an `(Rn)`/`(Qn)` tag or "supersedes"/"the user asked" narration in §1–4. That
  history is exactly ONE terse line in §5.1's Decisions log, nowhere else — see
  `analysis/_TEMPLATE.md`'s own style-rule comment. This is what keeps the doc readable after many
  review rounds instead of turning into a review-file transcript.
- The `↳ agent:` reply IS how the human sees what you did — make it a **concrete summary** (name
  the section + what changed), never a bare "fixed"/"done". No diff expected; the summary is it.
- After a review pass, **recap the resolved items back in chat** (one line each) so the human
  sees the changes without opening the file.
- **Never** write the Sign-off row — only the human clears a gate (`approved ✅`, date-time to the minute).
- Rejected execution result → the human adds items to `task/review/T0n.review.md` and sets the task
  `Status: verify-failed`; re-run it in its worktree and re-verify.
- **Open questions (QnA):** when you can't resolve something during analysis, don't guess — list
  it in the doc (`❓ Qn`) AND seed a `Qn` row in the review file's "## Open questions" section. The
  human answers with `↳ you:`; the next `/pw-review` folds the answer into the doc and flips the
  row to ✅ answered. Report unanswered `Qn` as blocking.
- **MR feedback:** review comments left on the *MR itself* are handled by `/pw-ship <slug> [task-ids]
  comments` (fetch via `glab`/`gh`, fix in the worktree, reply on the thread). **Task IDs are
  optional — with none it sweeps EVERY open MR** in the project in one run (serially). Always
  **mirror the change into the internal record** (task `## Result` + `task/review/` + `LOG.md`); the
  project dir stays the source of truth even for MR-driven fixes.
  - **⚠️ Never filter by diff-position to decide what's actionable.** GitHub needs two endpoints
    (`gh pr view --comments` + `gh api .../pulls/<n>/comments`) or inline review comments are
    missed; GitLab's `discussions` API returns everything in one call, but classify by
    `notes[].system`/`resolvable`/`resolved` — **not** `individual_note`, and **not** whether the
    note has a diff `position`. A general "Start thread" comment (no diff line) can be
    `resolvable: true` just like a diff comment — filtering on diff-position is a verified real bug
    that silently dropped an open reviewer thread entirely. Full field breakdown + a `jq` recipe:
    `tooling/docs/forges.md`.
  - **GitLab auto-resolves a diff thread when its line changes on a later push — it does NOT
    auto-resolve a resolvable *general* thread the same way.** Reply to a resolvable general thread
    AND explicitly resolve it (`glab api -X PUT …/discussions/<id> -f resolved=true`), or it'll look
    open forever even after being fixed.
  - **Idempotency for `resolvable: false` comments is local, not the forge's** — those can never
    report `resolved: true` no matter what. After replying to *any* thread, call
    `pw-lib.sh ship comment-seen <slug> <T0n> <thread-id> <resolvable|unresolvable> yes` — this
    upserts a row in `task/review/T0n.review.md`'s `## MR comment tracking` table, which the next
    `/pw-ship … comments` run checks before treating a thread as new. Same pattern as
    `pw-lib.sh rfc comment-seen` for RFC-platform comments.
  - **⚠️ `/discussions` can lag the raw notes table** (verified: 20+ min on a self-hosted GitLab, a
    real comment visible in the web UI, absent from the API the whole time). Cross-check freshness
    against `.../notes?sort=desc&order_by=updated_at` (a flat list, no `discussion_id` — useful only
    for detecting staleness, not for replying). If its newest non-system note isn't in the
    `/discussions` pull, don't report "nothing open" — retry, and if still missing, reply with a
    plain new top-level note (no `discussion_id` needed) and flag it in the recap for a human to
    verify once the real discussion syncs. Full flow: `tooling/docs/forges.md`.
- After a pass, report how many `🔴 open` items remain: `grep -rln "🔴 open" <project>/`.

## AI-assisted review (optional, per-phase opt-in)
Every review point above defaults to human-only. A project's dashboard `AI Review:` line
(`off`/`advisory`/`auto`, per phase) controls this — **the human-facing surface for viewing/setting
it is `/pw-review <slug> config [<phase> <mode>]`, never `pw-lib.sh ai-review` directly** (that's
the internal mechanism this sub-verb wraps; if I ever ask you how to change this, point me at the
command, not the script). Delegate a phase's review to the `pw-reviewer` sub-agent via `/pw-review
<slug> ai [phase|Tid|path]`:
- `advisory` — `pw-reviewer` files items exactly like a human would, tagged `(pw-reviewer,
  <timestamp>)` instead of `(you, …)`. A human still writes the Sign-off row; process its items via
  the normal apply-comments flow above, no different from a human's.
- `auto` — same filing, but if the pass leaves nothing 🔴/⏳ open, `pw-reviewer` may call
  `pw-lib.sh review auto-signoff <slug> <review-rel-path> <phase>` itself — the ONE tool-enforced
  exception to "only a human clears a gate", re-checked by the tool, not taken on trust.
`pw-reviewer` is spawned **fresh** (no shared context with whoever produced the artifact) and gets
handed only the artifact + review file + phase + `REVIEWER-NOTES.md` — never this session's own
reasoning about the artifact. **Loop prevention:** before filing, it checks the review file for an
existing item on the same section anchor — a 3rd item on the same anchor (i.e. a "fix" that already
recurred once) gets filed as a 🔴 open escalation instead of an ordinary finding, so `auto-signoff`
stays blocked by the tool's own check rather than by the reviewer remembering not to call it. Full
method: the `pw-review` skill. Full human-facing explanation: `docs/REVIEW.md`'s "AI-assisted
review" section.
