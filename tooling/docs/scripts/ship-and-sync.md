# Ship and sync scripts

The `/pw-ship` path lives in one entity script — `tooling/scripts/entities/pw-ship.sh`
(facets per `../conventions.md` S1b): decide what ships (`resolve`), push + open MRs (`exec`),
track MR/CI state (`mr-state`, `mr-state-batch`, `monitor`), record comment/bookkeeping
state (`comment-seen`, `dashboard-mr-state`), and the ship-owned **stack** lifecycle
(`stack`, `stack-validate`, `stack-plan`, `stack-record`, `stack-verify`, `stack-fresh`, `stack-stale`,
`stack-land`, `stack-promote`, `stack-retarget`, `stack-op`, `stack-debt`, `stack-adopt`).
The `history` family manages project-owned review-attempt records and verified description delivery.

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

A marked creation body is read back before its ownership snapshot is stored. Failure leaves the
MR URL recorded and reports initial snapshot pending; retain the creation body for a safe retry.
The marked body is also retained in the project record before readback. `history ... init <url>`
can retry from that payload without the temporary source file. No review attempt is created.

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
| `0` | `T03: pipeline SKIPPED (1m 2s) — no CI jobs ran for this push (repo pipeline rules)` | Terminal-**neutral**: every pipeline registered for the MR head sha was `skipped`. Not a failure — records `Build check: SKIPPED (no jobs …)`. Do NOT enter the build-fix loop on this |
| `1` | `T03: pipeline FAILED (2m 03s) — status: failed` | CI red/Cancelled; task file records `Build check: FAILED (…)` |
| `2` | `T03: pipeline still running after 30m — not yet resolved` | **timeout, not failure** — re-run or raise `--timeout` |

**Which pipeline it trusts (GitLab):** the MR's *head sha*, not "the first entry". Right after a
push the pipelines list can contain a **branch** pipeline that the repo's rules skip (the MR
pipeline registers a beat later) and a **stale** pipeline from the previous push — reading either
first produced, respectively, false `FAILED (skipped)` and false instant `SUCCESS` in live runs
(2026-09-23). The monitor filters the list to pipelines whose `sha` equals the MR head sha,
prefers a non-`skipped` status among those, and only concludes SKIPPED after two consecutive
skipped-only polls (registration grace). Requires `jq` for sha filtering; without it, falls back
to the older first-entry read.

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

## pw-ship.sh history

`history <slug> invocation` prints a call candidate ID; the caller retains it in its ledger.
`history <slug> pending` lists unfinished records without a forge query, including delivered history
whose main summary still needs repair. Discover these before merged/closed skips or worktree cleanup.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh history <slug> init <MR-url> --file <creation-body>
$PW_HOME/tooling/scripts/entities/pw-ship.sh history <slug> begin <MR-url> --invocation <call-id>
$PW_HOME/tooling/scripts/entities/pw-ship.sh history <slug> checkpoint <MR-url> --attempt <key> --file <JSON>
$PW_HOME/tooling/scripts/entities/pw-ship.sh history <slug> freeze <MR-url> --attempt <key>
$PW_HOME/tooling/scripts/entities/pw-ship.sh history <slug> deliver <MR-url> --attempt <key> --limit <n> --unit <utf8|chars> --limit-source <reference>
```

One invocation/MR produces one attempt. All intermediate fixes, commits, pipeline observations,
and replies checkpoint under that identity. Freeze seals the Before/After/Summary bullet groups,
commit bullets, and combined local/pipeline Verification. It does not create an MR, push, or reply.
The JSON checkpoint fields are documented in the command protocol; supplied evidence remains an
agent responsibility. Head binding and structural validation do not prove tests actually ran.

State lives in `<project>/.ship-history/<identity-hash>.json`, not a task worktree. It contains
versioned MR identity, full attempt archive, current ownership snapshot, ordering, pruning tombstones,
and any tentative delivery. Atomic file replacement runs behind an MR-specific exclusive directory
lock under the common projects root's `.ship-history-locks/`, so separate local projects cannot
concurrently write the same MR. Owner PID/token prevents releasing another writer's lock; no age-based takeover.
The library uses Python 3 stdlib, already used by bundle readers; no added package is required.

Delivery uses explicit host/repo endpoint arguments and JSON stdin. It rechecks the current body
before write, retries three observed read races, and verifies the landed body/head afterwards.
Only configured forge hosts (or their matching public defaults) are accepted. A new target must
be recorded in the project's task Result or MR table; verified existing archives remain recoverable
after task/worktree cleanup. This prevents an unrelated URL from becoming a new project-owned target.
The forge calls are not atomic conditional writes: a human can still race the final request.
A mismatch remains pending. Remote success before local acknowledgement is recovered by matching
owned-region snapshots, head, and retained history; it does not repeat pushes/replies or body writes.

Owned summary markers include all five sections through Notes for the reviewer. History is last,
newest first; retained frozen block bytes never change. Unknown ownership, malformed markers,
external edits inside a summary, or changed frozen blocks stop conflicting writes. Outside text
survives unchanged. A legacy unmarked summary permits history delivery only, explicitly summary pending.
After explicit owner review of a repaired currently published body, `history init --file <body> --reviewed`
can adopt its exact snapshot. This is human-triggered only, never an agent-initiative bypass. It rejects
changed or removed retained history. Frozen attempt bytes remain immutable.

Capacity is required per delivery: documented number, `utf8` bytes or Unicode `chars`, and source.
There is no guessed universal default. The GitLab instance-limit documentation reports approximately
1 million characters / 1 MB, not an exact cross-instance Unicode contract:
https://docs.gitlab.com/administration/instance_limits/#size-of-comments-and-descriptions-of-issues-merge-requests-and-epics
Resolve the actual instance policy before pruning. Unknown capacity fails safely without a write.
Remove only complete oldest blocks, retain the newest and all protected text, and keep the local
archive/tombstones. A newest block too large to fit remains pending; retries cannot resurrect pruned history.

Exit 0 means the requested operation completed; `history delivered; summary refresh pending` is
partial delivery and never a fully current-description claim. Exit 2 is an actionable validation,
ownership, locking, capacity, forge, or readback failure. Existing thread-tracking rows stay independent.
## Stack lifecycle (branch inheritance)

A task with a `Stacked on:` field inherits a same-repo parent's verified commit; its MR targets the
parent's branch until the parent lands. The `Stacked on:` field + ancestry/effective-target readers
live in `scripts/lib/pw-common.sh` (a library — callers never source it directly); these operators
are the deterministic surface. `stack`, `stack-plan`, and `stack-promote` read live Git ancestry;
`stack-land`, `stack-retarget`, and `exec` also read the forge (MR state/target) through the same
resolver as `mr-state`; the rest are offline.

```bash
S=$PW_HOME/tooling/scripts/entities/pw-ship.sh
$S stack <slug>                 # read-only topology + health: task|parent|target|branch|base|landed|freshness|debt
$S stack-validate <slug>        # fail-closed topology check (cycle, unknown/cross-repo parent, base drift, shared branch, missing depends_on); exit 1 on any finding
$S stack-plan <slug> [ids…]     # root-first publication order: task|repo|branch|target|parent|ready|reason (a stacked child is ready only once its target exists on origin)
$S stack-record <slug> <T0n> col=value…   # upsert binding columns (fork_sha, consumed_parent_sha, target, …); verification/landing columns are refused
$S stack-verify <slug> <T0n> <evidence> [--head <sha>] [--ci-sha <sha|skipped|pending|failed|unknown>] [--ci-target <branch>]
                                            # bind the verification tuple (current head + parent + effective target + evidence + CI disposition) in one atomic write after ## Verify
$S stack-fresh|stack-stale <slug> <T0n>    # force/clear the freshness flag (the tuple is always compared live, so the flag alone cannot certify)
$S stack-land <slug> <T0n> <merge-sha|-> <landed-into> [merge|ff|squash|rebase|closed|unknown]
                                            # verify + record a landing: merge/ff proven against a FETCHED origin ref + observed forge target; retains refs/pw-stack-landed/<slug>/<task>
$S stack-promote <slug> <T0n>   # promote|<target> | noop|<target> | block|<reason> (fetches first; the target must be published on origin)
$S stack-retarget <slug> <T0n> [--apply]   # move the MR base to the promoted target via the forge (dry-run; --apply: pending row first, state/target/head readback, loud local mirrors, no-op retry)
$S stack-op <slug> list|create|set|clear …   # pending-operation recovery rows (stages)
$S stack-debt <slug> [ids…]     # exit 1 + the pending ops touching the set (gates ship/comment/sync/close)
$S stack-adopt <slug> [--apply] [ids…]       # infer edges from real MR targets (dry-run; --apply writes)
$S stack-inherited <slug> <T0n> <parent> <sha>   # record one inherited update (Result bullet + LOG; never a reviewer comment)
$S stack-cascade <slug> <T0n> [--push] [--verify-cmd <cmd>] [--evidence-dir <dir>]
                                            # parent-first descendant propagation: integrate → verify-bind → record → push (shipped only, --push required); stages persist and resume
```

`stack-verify` writes the tuple (head, parent, target, evidence, CI disposition) in one atomic
record write, so a half-written binding can never certify anything; `skipped`/`pending` stay
explicit and a green bound to an old head or old target never carries across a retarget.
`stack-retarget` records its pending row before any forge write, checks the destination against
freshly fetched refs plus the MR's state/target/head, reads back target and head, and leaves the row
pending on any local failure — re-running resumes from the observed forge state without a duplicate
write. `stack-land` proves merge/ff landings only against fetched `origin` refs, corroborates the
forge MR target when the URL lets the forge answer, and retains the parent's verified tip as
`refs/pw-stack-landed/<slug>/<task>` so promotion survives source-branch deletion. `stack-cascade`
persists per-descendant stages (`integrate|verify|record|push|describe`) and resumes idempotently,
with its expected column recording the exact upstream commit sha; a shipped descendant's `describe`
stage clears only after its `history` delivery completes. An unstarted descendant (no branch
anywhere) gets its prerequisite head recorded and every stage skipped (terminal) — never a branch,
worktree, push, or Verify; an existing branch without a mounted worktree is integrated in a
worktree rehydrated at the approved task-worktree location, never by checking out the shared clone.
Stack writes take a PID/token lock with no automatic stale reclamation, and a state/op record whose
version header or row shape drifted is rejected before it can steer an operation.

The state files are `task/stack.tsv` (one row per affected task; machine TSV, never hand-edited)
and `task/stack-ops.tsv` (pending recovery rows). The `stack` preview distinguishes `unverified`
from `stale`: a never-started task with no tuple and no branch reads `unverified` (it must bind
before its own publication, but it does not block an ancestor's incremental ship), while a drifted
tuple, an explicit stale flag, a started task without a tuple, or a done/accepted task without its
binding reads `stale` and blocks. `_stack_stale` itself stays the strict execution gate. `exec`
uses the resolved effective target and
refuses a child whose target branch is not yet published on origin; once every ancestor has landed,
the effective target is the ultimate base and `exec` requires the base to be published instead of
matching an ancestor branch.
