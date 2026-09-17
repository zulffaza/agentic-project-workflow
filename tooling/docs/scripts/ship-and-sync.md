# Ship and sync scripts

The `/pw-ship` path lives in one entity script — `tooling/scripts/entities/pw-ship.sh`
(facets per `../conventions.md` S1b): decide what ships (`resolve`), push + open MRs (`exec`),
track MR/CI state (`mr-state`, `mr-state-batch`, `monitor`), and record comment/bookkeeping
state (`comment-seen`, `dashboard-mr-state`).

## pw-ship.sh resolve

Pre-computes the shippable set so `/pw-ship`'s agent reasons over a resolved list, not raw files.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh resolve <slug>
```

**Output** — one `|`-delimited line per task whose status is `done`:

```
T03|api-service|agent/myproj/T03-retry|main|PROJ-123|Wire retry into dispatcher|yes|no
```

Field order: `task-id | repo | branch | base-branch | ticket | title | has-real-commits | has-mr`.

**Reading it:** a line with `has-real-commits=no` means the "done" status is wrong — surface that,
don't ship it. Already has an MR → the task can go through sync/close-out instead. `0` lines =
nothing shippable (that's exit `0`, not an error). Exit `2` = usage / missing project / no PLAN.md.

## pw-ship.sh exec

The mechanical half of shipping **one task**, after the agent has confirmed the push list and
written the MR description: `git push`, then create the MR (`glab`/`gh`, per the forge registry).

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh exec <slug> <task-id> <description-file>
```

The description file's contents become the MR description — generating it stays an agent job;
pushing and filing is this script's job.

**Output** — progress lines ending in the URL:

```
Pushing agent/myproj/T03-retry to origin...
MR created: https://gitlab.example.com/group/api-service/-/merge_requests/42
Ship execution complete for T03
```

If the task's `- **MR:**` field holds a **real http(s) URL** it prints `MR already exists: <url>` and
stops (idempotent re-run); placeholder values (`-`, `—`, `(none)`, or no field) never count as an
existing MR. A successful creation upserts the URL into that same bold field. A
push failure dies with `pw-ship: push failed` (exit 2). If the push succeeded but the forge
CLI returned no MR URL, stderr carries the CLI's first error line + `MR creation failed (push
itself succeeded — safe to re-run after fixing auth/context)` — report that state honestly
(branch is public, no MR yet), fix auth/context, re-run. The forge CLI is picked from the repo's
origin host (github → `gh`, else `glab`).

**Prerequisite it validates for you:** `Repo:`/`Branch:` set in the task file and the repo present
locally — exit 2 messages name which is missing.

## pw-ship.sh mr-state-batch

One call instead of N `pw-ship.sh mr-state` queries.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh mr-state-batch <slug>            # every PLAN task, inferred
$PW_HOME/tooling/scripts/entities/pw-ship.sh mr-state-batch <slug> T03 T05    # just these
```

**Output** — one line per task: `T03|merged`, `T05|opened`, `T07|unknown`… `unknown` means the
query couldn't resolve state (no MR yet, forge CLI missing, task not in PLAN) — treat it as
"ask the forge", not as an error. Exit `2` only for usage/missing-project/missing-PLAN.

## pw-ship.sh monitor

Polls a task's MR pipeline to a terminal state after push — replaces agent-polling loops.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh monitor <slug> <task-id> [--timeout <minutes>] [--interval <seconds>]
```

Machine-reads the MR URL **from the task file's `## Result` only** (the bold `- **MR:**` field, with a
bare-URL fallback within that block — URLs elsewhere in the file, e.g. example endpoints in `## Steps`,
are deliberately ignored; keep only the true MR URL in `## Result`; `mr-state`, `ship-status`, and
preflight resolve it the same way). The forge host is resolved through `PW_FORGE_HOSTS` and the CLI env
(`GITLAB_HOST` etc.), so **source `pw.config.sh`** when running from a headless wrapper; an unknown host
exits 2 naming what's missing. Records the
outcome in the task file only — the dashboard's MR `State` column is deliberately untouched (CI
green ≠ merged; that column belongs to true merged-ness from `pw-ship.sh mr-state-batch`).

**Output + exit codes — the important part:**

| Exit | Last line looks like | Meaning |
|---|---|---|
| `0` | `T03: pipeline SUCCESS (4m 12s)` | CI green; the task's `- **Build check:**` field is upserted to `SUCCESS` (a template placeholder never blocks the record) |
| `1` | `T03: pipeline FAILED (2m 03s) — status: failed` | CI red/Cancelled; task file records `Build check: FAILED (…)` |
| `2` | `T03: pipeline still running after 30m — not yet resolved` | **timeout, not failure** — re-run or raise `--timeout` |

Intermediate `T03: pipeline running (…elapsed) — status: …` lines stream while polling. Exit `2`
is overloaded with usage errors — distinguish by message ("still running" = timeout). A query
that can't resolve state at all (no forge auth, bad MR id) fails fast after 3 consecutive
unreadable polls (`pipeline state unreadable after 3 polls — check <cli> auth and the MR id`)
instead of silently burning the whole timeout — fix the auth/context, then re-run. A pipeline
that simply isn't registered yet is *not* unreadable: it waits normally.

## pw-ship.sh mr-state

One task's MR state, straight from the forge: `open` | `merged` | `closed` — or `unknown`
(exit `1`) for any lookup failure (no MR URL in `## Result` or the dashboard table, no
worktree, no origin, unauthenticated CLI). The diagnostic goes to stderr prefixed `mr-state:`;
`unknown` on stdout is deliberate — callers skip, they don't die.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh mr-state <slug> T03
```

## pw-ship.sh comment-seen

The local authority for MR-comment threads the forge can never report resolved (plain
one-off comments — `resolvable: false`). Upserts ONE row per thread into the task review
file's `## MR comment tracking` table (hidden keyed marker; rerun the same thread → updated
in place, never duplicated; the section is created before `## Sign-off`, never after it).

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh comment-seen <slug> <task-id> <thread-id> resolvable|unresolvable yes|no [note...]
```

Kind/replied values are validated — anything else exits `2` without touching the table.
Don't reformat a row by hand; add a `note` argument instead.

## pw-ship.sh dashboard-mr-state

Sets one task's `State` cell in the dashboard's Merge-requests table (column-NAME driven —
never a fixed position; a missing table/column/row fails loudly and leaves the file
untouched). Used by the accept/merge flow; `exec` marks `open` on creation.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh dashboard-mr-state <slug> <task-id> merged
```
