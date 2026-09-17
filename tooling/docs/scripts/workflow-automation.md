# Workflow automation scripts

Side-loop helpers: the rfc-doc entity (`pw-rfc.sh` — the `comments` operator here; the
state operators `init`/`target`/`state`/`comment-seen`/`dashboard` are documented in
[`../rfc.md`](../rfc.md)) and the worktree entity (`pw-worktree.sh` — `create` here;
`remove`/`teardown` close-out guards below). Context fetch/adopt operators live in
[review-and-context-editing.md](./review-and-context-editing.md).

## pw-rfc.sh comments

Powers `/pw-rfc <slug> comments`: pulls reader comments from the configured RFC backend, tracks
them against `rfc/META.md`, and appends new items to `analysis/review/RFC.review.md`. Purely
mechanical — the agent's job starts at *triaging* what landed there.

```bash
$PW_HOME/tooling/scripts/entities/pw-rfc.sh comments <slug> [--backend <backend>]   # default: PW_RFC_BACKEND
```

**Output:** one summary line —

```
RFC comments: 3 new, 2 updated, 1 resolved externally
```

With the `markdown` backend (nothing external to fetch):
`RFC comments: no external comments to fetch (backend=markdown)` — exit `0`, that's success.

**Reading failures:** exit `2` messages point at setup, not at your review: `rfc/META.md not
found` / `no Target:` → run the publish step first; `lark-cli not found` → that backend's
dependency is missing (see `../rfc-backends.md`). After it runs, recap the new items to the user
and remind them to work the items via `/pw-review`.

## pw-worktree.sh create

Creates the execution worktree with the naming convention baked in — branch
`agent/<slug>/<task-id>-<suffix>`, path under the project's `worktree/` — so no agent hand-rolls
`git worktree add` and drifts from the layout `/pw-status`/`pw-teardown` expect.

```bash
$PW_HOME/tooling/scripts/entities/pw-worktree.sh create <slug> <task-id> <repo> <base-branch>
```

**Output:** status line(s), then **the worktree path on the final line** — capture that:

```
Creating worktree with new branch agent/myproj/T03-retry from origin/main...
Worktree created: /path/to/project/worktree/api-service-T03
/path/to/project/worktree/api-service-T03
```

Re-running is safe: an existing worktree prints `Worktree already exists: …` (exit 0); an
existing branch attaches instead of dying. Executor prompts receive this path — always create
before spawning, never let the executor `cd`- improvise.

**Reading failures:** exit 2 + `repo not found` (wrong repo dir name) or a git error (bad base
branch — fetch first, or the branch name is wrong).

## pw-worktree.sh remove / teardown

`remove <slug> <task-id>` — one task's worktree, used when its MR is already merged (refuses
a dirty tree or the worktree you're standing in — the guards live in `teardown`, the single
owner). `teardown <project-dir> [all|<task-id>] [worktree-path]` — the `/pw-close` sweep;
exit 1 = skipped with a printed reason, never a silent removal. Both were separate scripts
before the entity merge; operator semantics unchanged.
