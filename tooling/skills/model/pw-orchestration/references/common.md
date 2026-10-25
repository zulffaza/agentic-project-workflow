# pw-orchestration — common rules (every operation)

## Authorization and scope

Carry out only the authorized operation and its named selectors (`--project`, `--task`,
`--surface`, `--file`, and the operation's own words). Do not widen scope because another phase
looks unblocked.

An explicit human request authorizes the named work even without a literal slash command. It does
not authorize a different phase, a push, an approval row, or a destructive action.

Tool auto-approval is not workflow approval. Recorded sign-off, acceptance, and push confirmation
remain the only authorizations for those actions.

## Multiple operations in one request

When the human asks for several supported project operations together, use `/pw-batch` and load
`pw-guide-workflow` → `references/batch.md`. Preview is the default; apply must be explicit.
The `pw-batch` command file carries the closed allowlist. One request authorizes only its listed
operations: never infer approval, task acceptance, a phase move, a repair, or publication.

## Operation ownership

| Operation | Owns | Does not own |
|---|---|---|
| Human entry (`/pw-*`) | Dispatch, scope, gates, reporting | A reusable method's judgment rubric |
| `pw-guide-workflow` | Pipeline map and phase references | Dispatch or state writes |
| `pw-guide-review-method` | How a fresh reviewer assesses and files findings | Starting a review, approval, or repair |
| `pw-guide-authoring` | How analysis maps to RFC sections | Backend selection, publishing, comments |
| `pw-orchestration` (this skill) | Driver discipline, worker handoffs, checkpoints | Worker implementation, approval rows |

## Helpers, not hand edits

Mutate load-bearing state through the supported helpers: `pw-status.sh` (status, acceptance,
review advancement), `pw-review.sh` (review files, passes, sign-off), `pw-context.sh` (context
docs), `pw-doc.sh` (sync/lint), `pw-worktree.sh`, `pw-ship.sh`. Never hand-edit the dashboard
`Status:`, `LOG.md`, review-file structure, or a generated provider artifact.

Name the supported command path for discovery. Do not hand the human a script name, internal
operator syntax, or a manual state edit as their next step. If no command covers the request,
state the intended change and evidence in plain terms, then use the supported helper once the
request authorizes it.

## Read-only operations

Help, status reads, configuration reads, and doctor checks do not mutate state, spawn workers, or
run preflight writes. Report what was read and stop.

## Reporting

Report the affected artifact, evidence, resulting state, and any partial write in user terms.
State failures and skipped steps. Never describe a partial write as success. Do not cite internal
plan numbers, task IDs, or review-item anchors in committed code or MR-visible text; keep them in
the project record.
