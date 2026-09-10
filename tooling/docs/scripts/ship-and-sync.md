# Ship and sync scripts

The `/pw-ship` path: decide what ships (`pw-ship-resolve.sh`), push + open MRs
(`pw-ship-exec.sh`), then track MR/CI state (`pw-mr-state-batch.sh`, `pw-pipeline-monitor.sh`).

## pw-ship-resolve.sh

Pre-computes the shippable set so `/pw-ship`'s agent reasons over a resolved list, not raw files.

```bash
$PW_HOME/tooling/pw-ship-resolve.sh <slug>
```

**Output** — one `|`-delimited line per task whose status is `done`:

```
T03|api-service|agent/myproj/T03-retry|main|PROJ-123|Wire retry into dispatcher|yes|no
```

Field order: `task-id | repo | branch | base-branch | ticket | title | has-real-commits | has-mr`.

**Reading it:** a line with `has-real-commits=no` means the "done" status is wrong — surface that,
don't ship it. Already has an MR → the task can go through sync/close-out instead. `0` lines =
nothing shippable (that's exit `0`, not an error). Exit `2` = usage / missing project / no PLAN.md.

## pw-ship-exec.sh

The mechanical half of shipping **one task**, after the agent has confirmed the push list and
written the MR description: `git push`, then create the MR (`glab`/`gh`, per the forge registry).

```bash
$PW_HOME/tooling/pw-ship-exec.sh <slug> <task-id> <description-file>
```

The description file's contents become the MR description — generating it stays an agent job;
pushing and filing is this script's job.

**Output** — progress lines ending in the URL:

```
Pushing agent/myproj/T03-retry to origin...
MR created: https://gitlab.example.com/group/api-service/-/merge_requests/42
Ship execution complete for T03
```

If an MR already exists it prints `MR already exists: <url>` and stops (idempotent re-run). A
push failure dies with `pw-ship-exec: push failed` (exit 2). If the push succeeded but the forge
CLI returned no MR URL, stderr carries the CLI's first error line + `MR creation failed (push
itself succeeded — safe to re-run after fixing auth/context)` — report that state honestly
(branch is public, no MR yet), fix auth/context, re-run. The forge CLI is picked from the repo's
origin host (github → `gh`, else `glab`).

**Prerequisite it validates for you:** `Repo:`/`Branch:` set in the task file and the repo present
locally — exit 2 messages name which is missing.

## pw-mr-state-batch.sh

One call instead of N `pw-lib.sh mr-state` queries.

```bash
$PW_HOME/tooling/pw-mr-state-batch.sh <slug>            # every PLAN task, inferred
$PW_HOME/tooling/pw-mr-state-batch.sh <slug> T03 T05    # just these
```

**Output** — one line per task: `T03|merged`, `T05|opened`, `T07|unknown`… `unknown` means the
query couldn't resolve state (no MR yet, forge CLI missing, task not in PLAN) — treat it as
"ask the forge", not as an error. Exit `2` only for usage/missing-project/missing-PLAN.

## pw-pipeline-monitor.sh

Polls a task's MR pipeline to a terminal state after push — replaces agent-polling loops.

```bash
$PW_HOME/tooling/pw-pipeline-monitor.sh <slug> <task-id> [--timeout <minutes>] [--interval <seconds>]
```

Reads the MR URL from the task file's `## Result`, detects the forge from the URL. Records the
outcome in the task file only — the dashboard's MR `State` column is deliberately untouched (CI
green ≠ merged; that column belongs to true merged-ness from `pw-mr-state-batch.sh`).

**Output + exit codes — the important part:**

| Exit | Last line looks like | Meaning |
|---|---|---|
| `0` | `T03: pipeline SUCCESS (4m 12s)` | CI green; the task file records `- Build check: SUCCESS` |
| `1` | `T03: pipeline FAILED (2m 03s) — status: failed` | CI red/Cancelled; task file records `Build check: FAILED (…)` |
| `2` | `T03: pipeline still running after 30m — not yet resolved` | **timeout, not failure** — re-run or raise `--timeout` |

Intermediate `T03: pipeline running (…elapsed) — status: …` lines stream while polling. Exit `2`
is overloaded with usage errors — distinguish by message ("still running" = timeout). A query
that can't resolve state at all (no forge auth, bad MR id) fails fast after 3 consecutive
unreadable polls (`pipeline state unreadable after 3 polls — check <cli> auth and the MR id`)
instead of silently burning the whole timeout — fix the auth/context, then re-run. A pipeline
that simply isn't registered yet is *not* unreadable: it waits normally.
