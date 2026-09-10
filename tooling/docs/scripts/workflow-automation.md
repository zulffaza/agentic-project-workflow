# Workflow automation scripts

Side-loop helpers: RFC comments (`pw-rfc-comments.sh`), analysis context (`pw-context-fetch.sh`),
adoption snapshots (`pw-adopt-snapshot.sh`), worktree creation (`pw-worktree-create.sh`).

## pw-rfc-comments.sh

Powers `/pw-rfc <slug> comments`: pulls reader comments from the configured RFC backend, tracks
them against `rfc/META.md`, and appends new items to `analysis/review/RFC.review.md`. Purely
mechanical — the agent's job starts at *triaging* what landed there.

```bash
$PW_HOME/tooling/pw-rfc-comments.sh <slug> [--backend <backend>]   # default: PW_RFC_BACKEND
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

## pw-context-fetch.sh

First pass over the provenance table in `context/INDEX.md`: for every row, reads column 1
("File / link" — a bare URL, a ticket key like `PAYMXMP-5702`, a filename, or a markdown link)
and fetches the **CLI-handleable** ones — Jira (`jira issue view`), GitHub issues/PRs (`gh`),
GitLab issues/MRs (`glab`). Local filenames and "Repos in scope" rows are skipped; rows no CLI
can take are printed for the agent, never as errors:

- Lark URLs → `Lark URL — agent handles via platform skill`
- web URLs / unfetched non-URLs without a CLI → `(no CLI fetched this — agent handles via WebFetch
  / platform skill)`

```bash
$PW_HOME/tooling/pw-context-fetch.sh <slug> [--ignore-errors]   # --ignore-errors mirrors
                                                               # /pw-analyze's --ignore-fetch-errors
```

**Output:** per-row block — `Fetching: <cell> (<url>)` + the fetched content — then a final
`Context fetch complete`. Content already in the output must not be re-fetched; the agent still
handles every "agent handles" row (the Lark + WebFetch tail of the analysis fetch rules).

**Reading failures:** exit `1` is reserved for a bare ticket key with no `jira` CLI — printed as
`pw-context-fetch: N error(s):` with a per-row list; in `/pw-analyze` that's a STOP-and-ask.
`--ignore-errors` downgrades it to `NOT fetched … treat with reduced confidence`. Missing
`context/INDEX.md` is exit 2 (wrong slug / not scaffolded).

**When to use:** step zero of analysis, before any agent reads `context/`.

## pw-adopt-snapshot.sh

For `/pw-adopt` on a repo that already has in-flight branches: snapshots the git state and
resolves the base branch (explicit MR target → forge lookup via `gh`/`glab` → repo default).

```bash
$PW_HOME/tooling/pw-adopt-snapshot.sh <slug> <repo> <branch> [mr-url]
```

**Output** — flat `key: value`:

```
repo: api-service
branch: feat/retry-queue
base: main (mr-target)
mr-url: https://gitlab.example.com/group/api-service/-/merge_requests/42
commits: 7
files-changed: 12
```

`base:` parenthesizes **how** it was resolved (`mr-target` / `default`) — pass the `mr-url`
whenever you have one, so the base is the real MR target, not guesswork. Zero-commit / zero-file
snapshots are legitimate (branch just created); it's data for the adopt agent, not a green light.

**Reading failures:** exit 2 + `repo not found` / `branch not found` / `cannot determine base
branch` — fix the argument (repo dir name, branch name), or fetch, or pass the MR URL.

## pw-worktree-create.sh

Creates the execution worktree with the naming convention baked in — branch
`agent/<slug>/<task-id>-<suffix>`, path under the project's `worktree/` — so no agent hand-rolls
`git worktree add` and drifts from the layout `/pw-status`/`pw-teardown` expect.

```bash
$PW_HOME/tooling/pw-worktree-create.sh <slug> <task-id> <repo> <base-branch>
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
