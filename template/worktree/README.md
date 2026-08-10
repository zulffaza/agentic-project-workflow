# worktree/ — isolated working copies

Holds git worktrees checked out from the **real sibling repos** in `$PW_REPOS/`. Parallel
agents each get their own worktree so their edits never collide.

> Path vars: `$PW_REPOS` = repos root · `$PW_PROJECTS` = projects root. `bootstrap.sh` exports
> them; see the bundle's [REFERENCE.md]({{PW_HOME}}/docs/REFERENCE.md#who-fills-what-legend) legend.

Layout: `worktree/<repo>/<task-id>-<slug>/`

## Create (per task)
Fork from the task's **Base branch** (`origin/<base>`) — so tasks in one repo can target different
bases (e.g. `master` vs `spring3`):
```bash
git -C $PW_REPOS/<repo> fetch -q origin <base-branch>
git -C $PW_REPOS/<repo> worktree add \
  "$PW_PROJECTS/<project-slug>/worktree/<repo>/<task-id>-<slug>" \
  -b agent/<project-slug>/<task-id>-<slug> origin/<base-branch>
```

## Remove (after merge/abandon)
```bash
git -C $PW_REPOS/<repo> worktree remove \
  "$PW_PROJECTS/<project-slug>/worktree/<repo>/<task-id>-<slug>"
```

## Housekeeping
- List: `git -C $PW_REPOS/<repo> worktree list`
- Prune deleted ones: `git -C $PW_REPOS/<repo> worktree prune`
- These are **not copies** — deleting the folder by hand leaves a dangling entry; use
  `worktree remove` / `prune`.

> ⚠️ **KiloCode auto-approve can fail inside worktrees** — a worktree's `.git` is a file, not a
> directory, so some plugin config loaders miss the git boundary. Drive execution from Claude
> Code or approve manually if you hit this. (observed 2026-07-27.)

Nothing here is a source of truth — it's disposable working state. The truth is the commits on
the branches in the real repos.
