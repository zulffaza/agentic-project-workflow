# Git forge registry (shipment routing)

**Filled by:** [🤖 maintainer] — the day-to-day override you actually set is `PW_FORGE_HOSTS` in
`pw.config.sh` (a self-hosted GitLab host, or any forge whose CLI needs a host env var). This file
itself is maintainer-owned reference: the resolution algorithm + the Registry's exact CLI
invocations. `/pw-ship`/`/pw-adopt` READ this registry; you don't edit it day-to-day. The
gotchas below are summarized in [`docs/KNOWN-ISSUES.md`](../../docs/KNOWN-ISSUES.md).

`/pw-ship` (open MRs, fetch MR comments) and `/pw-adopt` (resolve an MR's target branch) both need
to know **which CLI talks to a given repo's Git host**. That's a per-repo fact, not a global one —
one project can touch a `github.com` repo and a self-hosted GitLab repo in the same run — so it's
resolved **per repo, from that repo's own `origin` remote**, never assumed globally.

## Resolution algorithm (what an agent does, every time it needs a forge)
1. `git -C <repo> remote get-url origin` → extract the host (the part between `://`/`@` and the
   first `/` or `:`).
2. **Exact-match** that host against `PW_FORGE_HOSTS` (an array of `"host=forge"` overrides in
   `pw.config.sh`) — if found, use that row's forge.
3. **Else auto-detect:** `github.com` → `github`; anything else (any other host at all, including
   `gitlab.com`) → `gitlab`. This covers the two common cases — a public GitHub repo or a public
   GitLab.com repo — with **zero configuration**. Only a **self-hosted** GitLab (or any forge whose
   CLI needs a host env var) needs one `PW_FORGE_HOSTS` line.
4. Look up the resolved forge in the Registry below for its CLI + invocation shape.

## Registry
| Forge | CLI binary | Host signal | Create-MR invocation | Fetch-comments invocation | Build/CI-status invocation | Notes |
|-------|-----------|--------------|----------------------|----------------------------|-----------------------------|-------|
| `github` | `gh` | `github.com` (default; no override needed) | `gh pr create` (run from inside the repo/worktree) | `gh pr view --comments` (standalone/general PR conversation comments) **+** `gh api repos/:owner/:repo/pulls/<n>/comments` (diff-anchored review comments) — **both**, or inline review comments are missed entirely | `gh pr checks <number>` — poll it (see § Build/CI status below) until every check reports a terminal `state`/`conclusion` | No host env var needed — `gh` resolves `github.com` on its own. |
| `gitlab` | `glab` | anything not `github.com` (default), or an exact `PW_FORGE_HOSTS` match | `GITLAB_HOST=<resolved-host> glab mr create` (run from inside the worktree) | `GITLAB_HOST=<resolved-host> glab api projects/:id/merge_requests/<iid>/discussions` — do **not** use `glab mr diff` for this, it only shows the code diff, no comments at all | `GITLAB_HOST=<resolved-host> glab api projects/:id/merge_requests/<iid>/pipelines` → take the newest entry's `id`, then poll `GITLAB_HOST=<resolved-host> glab api projects/:id/pipelines/<id>` for `.status` (see § Build/CI status below) | `<resolved-host>` = `gitlab.com` when auto-detected with no override, or the matched `PW_FORGE_HOSTS` host for a self-hosted instance. **Never hardcode a literal host in a command file** — that's the exact bug this registry fixes. |
| _`<future>`_ | _`<cli>`_ | _`<host signal>`_ | _`<invocation>`_ | _`<invocation>`_ | _`<invocation>`_ | Maintainer adds a row — no code change needed, but see "Adding a forge" below. |

## Standalone vs diff-anchored comments (both forges — read before writing a fetch-comments step)

> **⚠️ Corrected 2026-08-10.** An earlier version of this section claimed GitLab's `individual_note`
> field tells diff-anchored from standalone/general comments. **That's wrong** — verified against
> real production MR data (see `docs/REVIEW.md`'s note on this). `individual_note` means "single
> comment" vs "threaded reply chain," which is a different axis entirely: a **general** MR comment
> (posted from the Overview tab, not tied to any diff line) can *still* be `individual_note: false`
> and fully `resolvable: true` — GitLab lets you "Start a thread" on a general comment too, not just
> on a diff line. Do not gate fetching/actionability on `individual_note`, and do not gate it on
> whether the note has a diff `position` either — a real, verified case (GitLab MR, general/no-diff,
> `individual_note: false`, `resolvable: true`, `resolved: false`, containing a reviewer's
> unaddressed follow-up) was **completely missed** by an agent that filtered to diff-positioned
> notes only. Use the fields below instead — they were pulled and cross-checked directly against a
> real MR's raw API response, not inferred from docs prose.

**The three fields that actually matter, per note, regardless of diff-vs-general:**

| Field | Meaning | What to do |
|-------|---------|------------|
| `notes[].system` | `true` = GitLab's own activity log (approvals, "added 1 commit", the security-scan bot, description changes, "resolved all threads") — **never real reviewer feedback**. | Skip entirely. This is the real noise filter — not `individual_note`. |
| `notes[].resolvable` | Can this discussion *ever* report `resolved: true`? True for diff-anchored threads **and** general "Start thread" discussions alike. False = a genuine one-off standalone comment (posted as a plain "Comment", not a thread) — the forge can **never** mark it resolved, full stop. | `true` → trust `resolved` (below). `false` (and `system` isn't true) → this is the case the LOCAL tracking table exists for. |
| `notes[].resolved` | Only meaningful when `resolvable: true`. **GitLab auto-resolves a diff-anchored discussion when the underlying line changes on a later push** — that's why an already-fixed diff thread shows `resolved: true` with no explicit API call from anyone. **This auto-resolve does NOT happen for a resolvable discussion with no diff position** — pushing a fix to a *general* thread leaves it `resolved: false` forever unless something explicitly resolves it (`glab api -X PUT projects/:id/merge_requests/<iid>/discussions/<id> -f resolved=true`, or the GitHub equivalent). | After replying to a resolvable **general** thread, explicitly resolve it — don't assume a push will do it. |

**GitHub equivalent:** "issue comments" (`gh pr view --comments`) are always the standalone/general
kind, no resolved concept at all; "review comments" (`gh api repos/:owner/:repo/pulls/<n>/comments`)
are diff-anchored and support a resolve/thread API. Fetch **both** — `gh pr view --comments` alone
misses every inline review comment.

**Consequence for anything that loops "fetch → fix → reply → treat as done":** a thread with
`resolvable: false` can never show resolved on the forge, so you cannot use the forge's own
resolved/open state to decide whether it still needs handling — it will look "open" forever.
`/pw-ship … comments` handles this by tracking every thread it has already replied to — resolvable
or not — in a **local** table (`task/review/T0n.review.md`'s `## MR comment tracking`, via
`pw-lib.sh ship comment-seen`) instead of relying solely on the forge's resolved bit — see
[`docs/REVIEW.md`](../../docs/REVIEW.md#2-the-mr-review-flow-post-ship).

**Optional sanity check (if `jq` is available)** — run this after fetching, to mechanically list
what's still actionable instead of eyeballing a large JSON array (eyeballing is exactly how a real
open thread got missed):
```bash
GITLAB_HOST=<resolved-host> glab api "projects/:id/merge_requests/<iid>/discussions" | jq -c '
  .[] | select([.notes[].system] | all(. != true))          # drop pure system/activity discussions
      | select(.notes[-1].resolvable == false or .notes[-1].resolved == false)  # still actionable
      | {id, resolvable: .notes[-1].resolvable, resolved: .notes[-1].resolved,
         has_diff_position: (.notes[0].position != null), last_body: .notes[-1].body}'
```
`has_diff_position` in the output is informational only (tells you whether the fix is line-specific
or general) — it must never be used as the actionability filter itself.

## `/discussions` can lag the raw notes table — a freshness canary is required

> **⚠️ Verified 2026-08-10, self-hosted GitLab.** A brand-new, completely ordinary `DiffNote` (real
> diff position, `resolvable: true`, `system: false`, visible immediately in the GitLab web UI) was
> **still missing from `/discussions` 20+ minutes after being posted**, on both of two MRs it was
> left on. `/discussions` groups the raw notes table into threads server-side; on at least this
> instance, that grouping projection can lag the raw data by a meaningful amount — not seconds, and
> not reliably fixed by a short retry.

**Detecting it:** also fetch `glab api projects/:id/merge_requests/<iid>/notes?sort=desc&order_by=updated_at`
(GitHub: the newest entries from `gh api repos/:owner/:repo/pulls/<n>/comments` / issue comments) —
a flat list straight off the underlying table, with no `discussion_id` field (so it can't replace
`/discussions` for replying/resolving, only for detecting staleness). If that list's newest
`system == false` note isn't present anywhere in the `/discussions` pull, the `/discussions`
snapshot is stale — **do not conclude "nothing open."**

**Handling it once detected (no `discussion_id` available yet):** retry `/discussions` once or
twice with a short pause; if it's still missing, apply the fix and reply with a **plain new
top-level note** (`POST .../notes`, body only — no `discussion_id` required) quoting the file/line
and original text, note the lag explicitly in the reply, and record it in the local tracking table
as `unresolvable` with a note flagging it for a human to double check once the real discussion
eventually appears (the note ID and the eventual discussion ID aren't reconcilable from the API in
any straightforward way — don't try to auto-merge them later, just flag it). See
[`tooling/commands/pw-ship.md`](../commands/pw-ship.md)'s MR-comment mode step 1 for the full flow.

## Build/CI status (runs by default — `/pw-ship … --skip-build-check` opts out)

Build-check monitoring is **on by default** for `/pw-ship`, not a gate: it doesn't block the push
or the MR open/update, but it does mean a plain run now waits on CI before finishing. This is the
invocation an agent polls, per repo, after a push (see
[`tooling/commands/pw-ship.md`](../commands/pw-ship.md)'s own "Build check" section for exactly when
it fires in each mode, and how `--skip-build-check` disables it for a given run).

**Terminal states** (stop polling once you see one of these — anything else means keep polling):
- **GitHub** (`gh pr checks <number>`, or `gh pr checks <number> --json state,conclusion` for a
  scriptable read): each check's `state` reaches `COMPLETED`, at which point its `conclusion` is one
  of `SUCCESS` / `FAILURE` / `CANCELLED` / `SKIPPED` / `NEUTRAL`. Treat the run as terminal once
  every check has a `COMPLETED` state; the overall result is a failure if **any** check's
  `conclusion` is `FAILURE` or `CANCELLED`.
- **GitLab** (`glab api projects/:id/pipelines/<id>`): `.status` reaches one of `success` / `failed`
  / `canceled` / `skipped`. `pending`, `running`, and `created` are all non-terminal.

**Poll on an interval, with a timeout — never block indefinitely:**
- Re-check every ~30 seconds, up to a total budget of ~15 minutes.
- Still non-terminal at the budget → stop polling and report **"still running — not yet resolved"**
  (in the recap and the task's `## Result → Build check:` field) rather than hanging the rest of the
  `/pw-ship` run on one slow pipeline. This is a monitoring convenience, not a blocking gate — the
  push/MR-open/MR-update it's checking already happened before polling started.

**Report, never remediate.** A failed build is surfaced for a human to look at — this never triggers
an automatic pipeline retry/re-run, and it never rolls back or blocks the push/MR that's already out.
(Re-enqueuing an obviously-flaky CI failure is a judgment call for whoever's watching the MR
afterward — including an autonomous maintenance pass — not something the build check itself does.)

## Example config (`pw.config.sh`)
```sh
# A self-hosted GitLab needs exactly one line; public github.com/gitlab.com need none.
PW_FORGE_HOSTS=("git.internal.example.com=gitlab")
```
(That's a placeholder host for the example — put your **own** organization's real internal hostname
in your own gitignored `pw.config.sh`, never in a tracked file.)

## Adding a forge (extensibility — a maintainer task, not a quick edit)
Add one row to the Registry with its CLI binary, host-detection signal, and all three invocations
(create-MR, fetch-comments, build/CI-status). If it needs a host/instance env var the way `glab`
needs `GITLAB_HOST`, say so in the invocation column — the resolution algorithm above already
threads `<resolved-host>` through for you. No generator or script change is required; `/pw-ship`/
`/pw-adopt` read this file at ship/adopt time.
