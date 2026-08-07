# Git forge registry (shipment routing)

**Filled by:** [🧑 you] — this is config you maintain as you add forges/hosts, same shape as
[`providers.md`](./providers.md). `/pw-ship`/`/pw-adopt` READ this registry, they don't hardcode a
forge or host.

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
| Forge | CLI binary | Host signal | Create-MR invocation | Fetch-comments invocation | Notes |
|-------|-----------|--------------|----------------------|----------------------------|-------|
| `github` | `gh` | `github.com` (default; no override needed) | `gh pr create` (run from inside the repo/worktree) | `gh pr view --comments` | No host env var needed — `gh` resolves `github.com` on its own. |
| `gitlab` | `glab` | anything not `github.com` (default), or an exact `PW_FORGE_HOSTS` match | `GITLAB_HOST=<resolved-host> glab mr create` (run from inside the worktree) | `GITLAB_HOST=<resolved-host> glab api projects/:id/merge_requests/<iid>/discussions` (or `glab mr diff`) | `<resolved-host>` = `gitlab.com` when auto-detected with no override, or the matched `PW_FORGE_HOSTS` host for a self-hosted instance. **Never hardcode a literal host in a command file** — that's the exact bug this registry fixes. |
| _`<future>`_ | _`<cli>`_ | _`<host signal>`_ | _`<invocation>`_ | _`<invocation>`_ | Add a row — no code change needed. |

## Example config (`pw.config.sh`)
```sh
# A self-hosted GitLab needs exactly one line; public github.com/gitlab.com need none.
PW_FORGE_HOSTS=("git.internal.example.com=gitlab")
```
(That's a placeholder host for the example — put your **own** organization's real internal hostname
in your own gitignored `pw.config.sh`, never in a tracked file.)

## Adding a forge (extensibility)
Add one row to the Registry with its CLI binary, host-detection signal, and both invocations. If it
needs a host/instance env var the way `glab` needs `GITLAB_HOST`, say so in the invocation column —
the resolution algorithm above already threads `<resolved-host>` through for you. No generator or
script change is required; `/pw-ship`/`/pw-adopt` read this file at ship/adopt time.
