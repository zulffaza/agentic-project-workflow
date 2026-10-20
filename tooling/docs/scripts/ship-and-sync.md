# Ship and sync scripts

The `/pw-ship` path lives in one entity script — `tooling/scripts/entities/pw-ship.sh`
(facets per `../conventions.md` S1b): decide what ships (`resolve`), push + open MRs (`exec`),
track MR/CI state (`mr-state`, `mr-state-batch`, `monitor`), record comment/bookkeeping
state (`comment-seen`, `dashboard-mr-state`), and the ship-owned **stack** lifecycle
(`stack`, `stack-validate`, `stack-plan`, `stack-record`, `stack-verify`, `stack-fresh`, `stack-stale`,
`stack-land`, `stack-promote`, `stack-retarget`, `stack-op`, `stack-debt`, `stack-adopt`), and the
opt-in sync attempt/conflict surface (`sync-attempt`, `sync-merge`, `sync-finish`, `sync-bind`,
`sync-abort`).
The `history` family manages project-owned review-attempt records and verified description delivery;
`request-review` is the read-only review-request message generator.

## pw-ship.sh resolve

Pre-computes the shippable set so `/pw-ship`'s agent reasons over a resolved list, not raw files.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh resolve --project <slug>
```

**Output** — one `|`-delimited line per shippable task (PLAN Status `done` or `accepted`):

```
T03|api-service|agent/myproj/T03-retry|main|PROJ-123|Wire retry into dispatcher|yes|no
```

Field order: `task-id | repo | branch | base-branch | ticket | title | has-real-commits | has-mr`.

**Reading it:** `has-real-commits` is the count of the task's OWN commits on its LOCAL branch above
its effective comparison target (a `Stacked on:` child is compared against its parent's branch or
verified commit, so inherited commits never count as the child's own; an independent task is
compared against its `Base branch`). A line with `has-real-commits=no` means the "done" status is
wrong — surface that, don't ship it. Already has an MR → the task can go through sync/close-out
instead. `accepted` tasks appear too: opt-in auto-acceptance runs before any push, so an accepted
task with no MR is still eligible for an explicit shipment. When a candidate cannot be classified
(missing base ref, unavailable stacked parent), resolve prints a `→ fix:` line and exits `2`
**without emitting a partial list** — resolve the named item, then re-run. `0` lines = nothing
shippable (that's exit `0`, not an error). Exit `2` = usage / missing project / no PLAN.md.

## pw-ship.sh exec

The mechanical half of shipping **one task**, after the agent has confirmed the push list and
written the MR description: `git push`, then create the MR (`glab`/`gh`, per the forge registry).

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh exec --project <slug> --task <task-id> --file <description-file>
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
existing MR. With no recorded URL, the script still looks up an MR for the same source branch before
creating one: a previous attempt whose response was lost is adopted and recorded instead of being
duplicated. A successful creation upserts the URL into that same bold field. The dashboard MR
`State` mirrors what exists: a new MR writes `open`, while a continuation on a merged or closed MR
keeps that terminal state instead of reopening it. A
push failure dies with `pw-ship: push failed` (exit 2). If the push succeeded but the forge
CLI returned no MR URL, stderr carries the CLI's first error line + `MR creation failed (push
itself succeeded — safe to re-run after fixing auth/context)` — report that state honestly
(branch is public, no MR yet), fix auth/context, re-run. The forge CLI is chosen from the
**configured** forge for the repo's origin host (an exact `PW_FORGE_HOSTS` entry wins, else
`github.com` → `gh`, else `glab`) and resolved **before** the push: a missing required CLI
refuses the shipment instead of pushing a branch with no MR path or silently switching forges.
The same pre-push step probes the installed `glab` for `mr create --output json`; a release
without that contract uses the plain invocation (which prints the MR URL) instead of failing
after the branch is public. Creation output is parsed structurally and independently of
whitespace, and the recorded URL is verified inside the task's `## Result` before completion is
reported — an MR-looking line elsewhere in the file is never the one rewritten.

A marked creation body is read back before its ownership snapshot is stored. Failure leaves the
MR URL recorded and reports initial snapshot pending; retain the creation body for a safe retry.
The marked body is also retained in the project record before readback. `history --project <slug>
--operation init --mr <url>` can retry from that payload without the temporary source file. No review attempt is created.

**Prerequisite it validates for you:** `Repo:`/`Branch:` set in the task file and the repo present
locally — exit 2 messages name which is missing.

## pw-ship.sh mr-state

Reads the recorded MR URL from `## Result` (else the dashboard row) and derives forge, host,
repository, and IID **from that URL**, so a state read still works after the task's worktree — or the
whole project checkout — is gone. A validated checkout is used as the CLI context when present; the
repository field names a shared clone otherwise, and a fully absent checkout falls back to the
forge API with the URL's explicit repository identity (needed for enterprise GitHub, where the
origin-pattern guess used to yield an empty repo). Configured `PW_FORGE_HOSTS` still wins over the
URL-derived forge. `unknown` means the state could not be read (auth/URL), never a guessed value.

## pw-ship.sh mr-state-batch

One call instead of N `pw-ship.sh mr-state` queries.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh mr-state-batch --project <slug>            # every PLAN task, inferred
$PW_HOME/tooling/scripts/entities/pw-ship.sh mr-state-batch --project <slug> --task T03 --task T05    # just these
```

**Output** — one line per task: `T03|merged`, `T05|opened`, `T07|unknown`… `unknown` means the
query couldn't resolve state (no MR yet, forge CLI missing, task not in PLAN) — treat it as
"ask the forge", not as an error. Exit `2` only for usage/missing-project/missing-PLAN.

## pw-ship.sh monitor

Polls a task's MR pipeline to a terminal state after push — replaces agent-polling loops.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh monitor --project <slug> --task <task-id> [--timeout <minutes>] [--interval <seconds>]
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
| `2` | `T03: pipeline still running after 30m — not yet resolved` | **timeout, not failure** — re-run or raise `--timeout`. Records `Build check: UNRESOLVED (timeout …)` so a previous `SUCCESS` cannot describe the latest run |

**Which pipeline it trusts (GitLab):** the MR's *head sha*, not "the first entry". Right after a
push the pipelines list can contain a **branch** pipeline that the repo's rules skip (the MR
pipeline registers a beat later) and a **stale** pipeline from the previous push — reading either
first produced, respectively, false `FAILED (skipped)` and false instant `SUCCESS` in live runs
(2026-09-23). The monitor filters the list to pipelines whose `sha` equals the MR head sha,
prefers a non-`skipped` status among those, and only concludes SKIPPED after two consecutive
skipped-only polls (registration grace). The head sha is read structurally (`jq`, or a
whitespace-tolerant read without it), so a pretty-printed MR body still yields the identity.
Head filtering needs `jq`; without it the monitor does **not** fall back to a sha-blind first
entry — it keeps polling and settles as an honest unresolved timeout rather than a false green.

**GitHub checks:** the monitor reads `gh pr checks --json state` and aggregates every selected
check, so one failing check cannot hide behind another. Failed-ish (`FAILURE`, `CANCELLED`,
`TIMED_OUT`, `ACTION_REQUIRED`, `STARTUP_FAILURE`) is a failed run; any pending-ish state
(`PENDING`, `QUEUED`, `IN_PROGRESS`, `WAITING`, `REQUESTED`, `EXPECTED`) blocks a green verdict;
all `SUCCESS`/`SKIPPED`/`NEUTRAL` is green, and an all-`SKIPPED` set keeps the existing skipped
semantics. An empty list reads as "no checks yet" and keeps polling. The previous table read
dropped the first row and reduced the rest to one sorted status.

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
$PW_HOME/tooling/scripts/entities/pw-ship.sh mr-state --project <slug> --task T03
```

## pw-ship.sh comment-seen

The local authority for MR-comment threads the forge cannot decide by its own resolved bit —
plain one-off comments (`resolvable: false`) can never report resolved, and since `/pw-ship …
comments` leaves handled threads open by default, a `resolvable: true` thread it fixed is still open
too. Upserts ONE row per thread into the task review file's `## MR comment tracking` table (hidden
keyed marker; rerun the same thread → updated in place, never duplicated; the section is created
before `## Sign-off`, never after it).

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh comment-seen --project <slug> --task <task-id> --thread <thread-id> --kind <resolvable|unresolvable> --replied <yes|no> [--note <note…>] [--feedback <token>] [--reply <token>] [--head <sha>]
```

Kind/replied values are validated — anything else exits `2` without touching the table.
The optional evidence flags record *why* the current feedback is handled: `--feedback` = the
reviewer-feedback revision seen (latest actionable note id, or a short fingerprint), `--reply` =
the agent's own reply id, `--head` = the verified published head. When any is given, a hidden
`<!-- pw-mr-ev:… -->` marker is appended to the row (a plain call keeps the exact legacy row
shape); the next `/pw-ship … comments` run uses it to skip an unchanged handled thread and to let
`--resolve` close it without re-fixing. A row with no evidence marker is not proof of handling.
Don't reformat a row by hand; add a `--note` value instead.

## pw-ship.sh dashboard-mr-state

Sets one task's `State` cell in the dashboard's Merge-requests table (column-NAME driven —
never a fixed position; a missing table/column/row fails loudly and leaves the file
untouched). Used by the accept/merge flow; `exec` marks `open` on creation.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh dashboard-mr-state --project <slug> --task <task-id> --state merged
```

## pw-ship.sh history

`history --project <slug> --operation invocation` prints a call candidate ID; the caller retains it in its ledger.
`history --project <slug> --operation pending` lists unfinished records without a forge query, including delivered history
whose main summary still needs repair. Discover these before merged/closed skips or worktree cleanup.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh history --project <slug> --operation init --mr <MR-url> --options --file <creation-body>
$PW_HOME/tooling/scripts/entities/pw-ship.sh history --project <slug> --operation begin --mr <MR-url> --options --invocation <call-id>
$PW_HOME/tooling/scripts/entities/pw-ship.sh history --project <slug> --operation checkpoint --mr <MR-url> --options --attempt <key> --file <JSON>
$PW_HOME/tooling/scripts/entities/pw-ship.sh history --project <slug> --operation freeze --mr <MR-url> --options --attempt <key>
$PW_HOME/tooling/scripts/entities/pw-ship.sh history --project <slug> --operation deliver --mr <MR-url> --options --attempt <key> --limit <n> --unit <utf8|chars> --limit-source <reference>
$PW_HOME/tooling/scripts/entities/pw-ship.sh history --project <slug> --operation validate --options --file <description>
```

`validate` runs the SAME managed-marker parser delivery uses over the whole description and is a
read-only gate: it prints `validate: ok (<n> chars)` or exits `2` naming the boundary failure. `exec`
calls it automatically on a description that carries the managed markers, **before the push**, so a
malformed boundary (for example literal `\n` separators appended after the end marker) cannot be
published by a workflow-owned create.

`capacity --mr <url>` resolves the description capacity for the MR's host and persists it under
`.ship-history/capacity/<host>.json`. Order: explicit `--limit/--unit/--limit-source` (recorded as
`explicit-override`), then the persisted policy, then one instance-settings probe (a 403 is retried
once after two seconds), then the documented fallback of `1048576 chars` with reason
`settings-403; official-docs-fallback`. A fallback is never reported as instance-verified. `deliver`
uses the persisted policy when the flags are omitted, so other MRs on the same host reuse it without
repeating the probe.

`migrate --mr <destination> --source <source-mr> --attempts <key[,key]> [--apply]` carries verified
frozen attempts from a replaced/adopted MR into the destination record. It is a preview by default;
`--apply` persists atomically under the destination lock. Each source record must exist, the two
MRs must share host and repository, every selected attempt must be frozen, and the destination body
must contain that attempt's exact frozen block; a conflicting destination key or an edited block is
refused. Migrated entries keep the original key, timestamp, block, and checkpoint, gain
`source_mr`/`source_delivered` provenance, start undelivered (source delivery debt is never copied),
and a retry is idempotent. The source record is never modified. When the source record is not in the
current project, sibling project directories are searched (read-only) and the location is named, so an
archived project's history is never reported as lost.

`verify --mr <url>` is the post-navigation readback: it fetches the published body and runs that same
parser, printing `verify: ok (head …)` or exiting `2` with the reason. Use it after an agent edits a
parent MR's navigation. `repair-preview --mr <url>` is a dry run for the known suffix: it reports the
literal characters appended after an end marker, the exact repaired line, and how many characters the
repair removes — and never writes. Apply the repair to the description, then run `verify`.

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
newest first; each attempt is collapsed in its own `<details>` wrapper labeled
`Review attempt: <D MMMM YYYY - HH.mm WIB>` (presentation only — the enclosed frozen bytes never
change), and a legacy unwrapped attempt is recognized during transition and converts on the next
authorized delivery. New event datetimes carry the dashed separator; readers still accept the
legacy undashed form, and an already-frozen heading keeps its original bytes. Unknown ownership, malformed markers,
external edits inside a summary, or changed frozen blocks stop conflicting writes. Outside text
survives unchanged. A legacy unmarked summary permits history delivery only, explicitly summary pending.
After explicit owner review of a repaired currently published body, `history --project <slug>
--operation init --options --file <body> --reviewed`
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
## pw-ship.sh request-review

Read-only: generates ONE copyable teammate review-request message for all (or a selected set of)
open recorded project MRs. No forge writes, no project writes, no CI polling — it reads each
unique MR once, applies the selection rules, validates the frame and any optional prose, reads
only the enabled generation prompts, and prints a selection recap plus one fenced message.

```bash
$PW_HOME/tooling/scripts/entities/pw-ship.sh request-review --project <slug> [--all | --task <task-id>]… \
  [--to <names>] [--summary] [--mr-summary] [--note] [--no-reviewers] [--prose <file>]
```

- **Selection** follows stable PLAN order: the task-file `## Result → MR:` line first, with the
  same dashboard fallback the other readers use; a task-file link that disagrees with the
  dashboard is a recorded-links conflict that stops the run before any message. `--all` reports
  (and excludes) tasks without an MR and merged/closed MRs in the recap; an explicit `--task` id in
  any of those states stops instead. One entry per unique MR; several tasks sharing one MR emit
  one entry and are reported together.
- **Metadata** per unique MR comes from one bounded read-only forge call each: title, state,
  draft, target branch, assigned reviewers, description (fetched when any prose flag is enabled,
  including `--note` alone), and head-specific build status. CI status renders the observed
  state (`passed`/`failed`/`running`/`pending`/`canceled`/`skipped`) or `unavailable`
  when that read fails or has no head-specific result — never a readiness claim. Unknown hosts go
  through the same registry/`PW_FORGE_HOSTS` resolution as `history`.
- **Rendering** uses built-in title-led blocks (Link / Branch Target / CI Status / Assigned
  Reviewer / per-MR Summary / Draft / Landing unit / Stacked on) substituted into the frame file —
  `user/templates/review-request.md` by default, or `PW_REVIEW_REQUEST_TEMPLATE_FILE` (a relative
  path resolves under `$PW_HOME`; the older implicit default `user-templates/review-request.md`
  migrates byte-for-byte through the doctor). The frame is validated before any forge query: each
  of `{{TO_BLOCK}}`, `{{SUMMARY_BLOCK}}`, `{{MR_BLOCKS}}`, `{{NOTE_BLOCK}}` exactly once,
  `{{PROJECT}}` at most once, no other token.
- **Generation prompts**: `--summary`/`--mr-summary` share
  `user/prompts/review-request-summary.md` (or `PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE`); `--note`
  reads `user/prompts/review-request-note.md` (or `PW_REVIEW_REQUEST_NOTE_PROMPT_FILE`). Only
  enabled prompts are read, once per pass, as UTF-8 text at most 16 KiB — never sourced or
  executed, and a direct `--prose` supply reads none. An invalid enabled prompt omits its affected
  sections (a summary-prompt failure affects both summary modes) with a diagnostic naming the
  path, source, and correction; missing defaults point to `/pw-doctor --fix` and the helper never
  creates or repairs prompt files. The effective path/source stays visible in the generation
  diagnostics, outside the copyable message.
- **AI prose** (`--summary`, `--mr-summary`, `--note`) is authored by the caller and supplied back
  through `--prose` as JSON — `{"summary": "…", "mr_summaries": {"<MR url>": "…"}, "note": ["…"],
  "omit": ["<section>"]}` — and validated for membership, presence, and sentence/word limits
  (summary 2 sentences/50 words; per-MR 2/35; note 3 bullets/60 words total) before insertion.
  Without `--prose`, the first run prints the deterministic message (requested sections absent),
  a bounded evidence packet (descriptions, task-result excerpts, and — only when a description
  cannot explain the change and the MR records target + head — a read-only diff of that MR's own
  target…head delta, so a stacked MR's inherited parent changes never enter), the enabled prompt
  text, and the pending-section diagnostics; the deterministic message always survives AI failure
  or an explicit omit.
- **Evidence budgets**: 12,000 characters per selected MR (description, task excerpts, optional
  diff, in that order) and 48,000 characters aggregate; identity/head lines always survive and
  every trim is labeled. A truncated or unavailable description is a limitation, never proof that
  no relevant detail exists. Diff retrieval is conditional on enabled prose and a concrete
  evidence gap; ordinary runs make no extra forge calls.
- **Observed heads** print in both calls' diagnostics (`observed heads: <url> <sha>; …`) so the
  caller can compare them before relaying the final message: a newer head on the second call
  discards the affected prose for one regeneration from current evidence; a second move omits the
  affected section. This bounded check detects observed changes and does not claim to freeze
  remote MRs.
- Exit `2` = usage / missing project / missing PLAN / conflicting or failed lookup / invalid frame
  or prose; exit `0` also covers the explained empty selection (no message emitted). Read-only
  battery row: `request-review F1` pins the no-PLAN stop path.

## Stack lifecycle (branch inheritance)

A task with a `Stacked on:` field inherits a same-repo parent's verified commit; its MR targets the
parent's branch until the parent lands. The `Stacked on:` field + ancestry/effective-target readers
live in `scripts/lib/pw-common.sh` (a library — callers never source it directly); these operators
are the deterministic surface. `stack`, `stack-plan`, and `stack-promote` read live Git ancestry;
`stack-land`, `stack-retarget`, and `exec` also read the forge (MR state/target) through the same
resolver as `mr-state`; the rest are offline.

```bash
S=$PW_HOME/tooling/scripts/entities/pw-ship.sh
$S stack --project <slug>                 # read-only topology + health: task|parent|target|branch|base|landed|freshness|debt
$S stack-validate --project <slug>        # fail-closed topology check (cycle, unknown/cross-repo parent, base drift, shared branch, missing depends_on); exit 1 on any finding
$S stack-plan --project <slug> [--task <T0n>]…     # root-first publication order: task|repo|branch|target|parent|ready|reason (a stacked child is ready only once its target exists on origin AND that ref sits at the parent's verified head — presence alone is not proof)
$S stack-record --project <slug> --task <T0n> --set <col=value> [--set <col=value>]…   # upsert binding columns (fork_sha, consumed_parent_sha, target, …); verification/landing columns are refused
$S stack-verify --project <slug> --task <T0n> --evidence <path> [--head <sha>] [--ci-sha <sha|skipped|pending|failed|unknown>] [--ci-target <branch>]
                                            # bind the verification tuple (current head + parent + effective target + evidence + CI disposition) in one atomic write after ## Verify
$S stack-fresh|stack-stale --project <slug> --task <T0n>   # force/clear the freshness flag (the tuple is always compared live, so the flag alone cannot certify)
$S stack-land --project <slug> --task <T0n> --merge-sha <sha|-> --landed-into <branch> [--kind <merge|ff|squash|rebase|closed|unknown>]
                                            # verify + record a landing: merge/ff proven against a FETCHED origin ref + observed forge target; retains refs/pw-stack-landed/<slug>/<task>
$S stack-promote --project <slug> --task <T0n>   # promote|<target> | noop|<target> | block|<reason> (fetches first; the target must be published on origin)
$S stack-retarget --project <slug> --task <T0n> [--apply]   # move the MR base to the promoted target via the forge (dry-run; --apply: pending row first, state/target/head readback, loud local mirrors, no-op retry)
$S stack-op --project <slug> list|create|set|clear …   # pending-operation recovery rows (stages)
$S stack-debt --project <slug> [--task <T0n>]…     # exit 1 + the pending ops touching the set (gates ship/comment/sync/close)
$S stack-adopt --project <slug> [--apply] [--task <T0n>]…       # infer edges from real MR targets (dry-run; --apply writes)
$S stack-inherited --project <slug> --task <T0n> --parent <T0n> --parent-sha <sha>   # record one inherited update (Result bullet + LOG; never a reviewer comment)
$S stack-cascade --project <slug> --task <T0n> [--push] [--verify-cmd <cmd>] [--evidence-dir <dir>] [--on-conflict <abort|keep>]
                                            # parent-first descendant propagation: integrate → verify-bind → record → push (shipped only, --push required); stages persist and resume

```
**Freshness proof applies to every task, not only stacked children.** `exec` refuses to publish when
the task has a recorded verification tuple and `_stack_stale` no longer matches live Git/state — the
branch head moved after verification, the consumed parent advanced, the effective target changed, or
the CI binding no longer covers the current head. A ROOT task used to bypass these gates entirely,
so a post-verification commit could be published under stale evidence. Tasks with no recorded tuple
keep the legacy path.

**Cascade verification stages.** With no `--verify-cmd`, a cascade defers: it exits `1` (pending,
not failed), names the exact manual step, and leaves the verify stage pending. A later invocation
resumes as soon as `stack-verify --head` has bound the child's current commit — it does not repeat
the advice forever. When a `--verify-cmd` runs, the checkout must be unchanged afterwards: a command
that commits or leaves tracked edits has certified a different snapshot than the one to be bound, so
the stage blocks and nothing is pushed.

**Resume semantics.** A `blocked` push stage is retried on the next authorized run (only `done` /
`skipped` are terminal), so a transient rejection no longer strands the subtree. A completed verify
stage is re-opened when the child head is no longer the bound commit (a later integrate can move it),
so a stale binding can never certify newer work. A descendant recorded as landed is terminal: the
cascade marks its stages `skipped` and never integrates, re-verifies, or pushes it again.


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

## Opt-in sync conflict resolution

`/pw-sync` keeps its default behavior: a conflicting merge aborts and the task goes back for manual
resolution. With `--auto-resolve`, the command records one attempt, leaves the conflict in place for
the agent, and publishes only after verification binds to the final HEAD. The deterministic surface
is these operators; the reasoning procedure lives in
`tooling/skill/project-workflow/references/sync-conflict-resolution.md` and loads only for an
opt-in run or a resume.

```bash
S=$PW_HOME/tooling/scripts/entities/pw-ship.sh
$S sync-attempt begin --project <slug> --task <T0n> --kind <independent|stack> --mode auto --target-branch <branch>
                                                 # pin start HEAD, origin/<task-branch>, target branch + SHA
$S sync-attempt show --project <slug> [--task <T0n>]     # recorded attempts (machine TSV rows)
$S sync-attempt check --project <slug> --task <T0n>      # fresh (0) | stale: reason (1) against fetched refs
$S sync-merge --project <slug> --task <T0n> --target <sha> --keep-conflict
                                                 # 0 clean/contained; 3 conflict kept for resolution; 2 aborted/failed
$S sync-finish --project <slug> --task <T0n>     # complete the attempt-owned merge (needs staged paths, no unmerged/markers)
$S sync-bind --project <slug> --task <T0n> --evidence <path>
                                                 # require clean tree + recorded result HEAD, then bind verified evidence
$S sync-attempt set --project <slug> --task <T0n> --stage <failed|pushed> [--repair 0|1]
$S sync-abort --project <slug> --task <T0n>      # abort only the attempt-owned merge; report untracked files
```

The attempt record is `task/sync-attempts.tsv`: one row per task with the pinned tuple
(`start_head`, `remote_head`, `target_branch`, `target_sha`), stage
(`prepared → conflict → resolved → verified → pushed`, or `failed`), the repair count, the result
head, evidence path, and timestamps. It is machine-owned, written under a lock by the operators,
and rejected on a drifted header or row shape. `check` compares the live fetched refs and the
worktree HEAD with that tuple; a stale result blocks publication. Stage transitions for the merge
lifecycle are operator-owned, so a caller cannot skip verification by setting a stage directly.

`stack-cascade --on-conflict keep` is the guarded handoff for a descendant integration. Instead of
aborting internally, it leaves the conflicted merge in the descendant worktree, marks
`integrate=blocked`, and blocks the subtree. After the agent resolves and commits, the caller marks
the stage done (`stack-op set --key <opkey> --state <T0n>:integrate=done`) and re-runs the cascade;
the remaining verify/record/push stages resume. This path does not push.

Verification remains authoritative: `sync-bind` only records evidence for a clean worktree at the
committed result HEAD, and a stack member must also rebind `stack-verify` (final head, verified
parent, effective target, CI disposition) before descendants advance. Never report local resolution
alone as a successful sync, and never substitute a pre-push `pending` CI marker for CI success.
