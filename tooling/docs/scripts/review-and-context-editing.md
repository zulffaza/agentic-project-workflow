# Review and context editing scripts

Deterministic writes to the two human-edited document families: review files
(`pw-review.sh`) and the context docs (`pw-context.sh`). Both exist so nobody hand-copies
template blocks or hand-matches house style — every heading, marker, timestamp, `---` rule,
table row, and reindex is written by the script. Placement rules for these (and any future)
scripts/operators: [`../conventions.md`](../conventions.md).

## pw-review.sh

The review-doc entity: write side, `scan`, and the lifecycle/gate reads (`gate|count|has-open`)
 — all operators of `pw-review.sh`.

```bash
$PW_HOME/tooling/scripts/entities/pw-review.sh init-all <slug>
    # create every missing review file: analysis/<topic>.md, task/PLAN.md, each task/T0n.md
    # → sibling review/<name>.review.md (via pw-review.sh init). Idempotent; exit 0 always.

$PW_HOME/tooling/scripts/entities/pw-review.sh signoff <slug> <review-rel-path> <decision> [--by <name>]
    # append a Sign-off row: decision ∈ approved | changes-requested | in-review.
    # HUMAN-TRIGGERED ONLY (C4) — an agent runs this only verbatim on the user's explicit
    # instruction, never on its own initiative; the agent-side path is
    # pw-review.sh auto-signoff (mode=auto + zero open items only).
    # Append-only: existing rows are history and are never edited or deleted. The first
    # sign-off replaces the template's lone "| | | in-review |" placeholder row.

$PW_HOME/tooling/scripts/entities/pw-review.sh add-item <slug> <review-rel-path> --section <§anchor> (--text <ask…> | --stdin) [--actor <name>]
    # append the next Rn block at the end of ## Items: heading + timestamp + (actor,…) +
    # <!-- pw-item-status: open --> marker + body + --- rule, then reindex ## Contents.
    # Fills the template's unfilled R-stub in place (no phantom duplicate R1).
    # Ids stay monotonic across archives (archived <!-- pw-archived:Rn --> markers counted).
    # --actor defaults to "you"; only pw-review/pw-reviewer surfaces pass --actor "pw-reviewer".

$PW_HOME/tooling/scripts/entities/pw-review.sh answer <slug> <review-rel-path> <Qid> (--text <answer…> | --stdin)
    # append your "> ↳ **you** (<now>): …" line under question Qid — same quoted block, blank
    # quoted ">" separator between consecutive ↳ lines. Refuses missing/[ANSWERED] questions.
    # Does NOT flip the status: the agent folds the answer into the doc and flips it (doctrine).

$PW_HOME/tooling/scripts/entities/pw-review.sh add-question <slug> <review-rel-path> --section <§anchor> (--text <q…> | --stdin) [--actor <name>]
    # agent-side: append the next Qn block ([PENDING] + open marker) at the end of
    # ## Open questions, then reindex. Fills the template's Q-stub in place.

$PW_HOME/tooling/scripts/entities/pw-review.sh resolve <slug> <review-rel-path> <Rid|Qid> (--reply <text…> | --stdin)
    # agent-side: flip the SAME heading in place ([OPEN]→[RESOLVED] / [PENDING]→[ANSWERED],
    # tag + marker together — never a second heading) and append the quoted
    # "> ↳ **agent** (<now>): …" reply below the ask/answer, then reindex.
    # A Qid refuses unless a "↳ **you**" line already exists — never answers for the human.
    # Human text is never edited or deleted (mutation-tested).
```

**Free-text arguments (A-rules, [`../conventions.md`](../conventions.md)):** `--text` consumes
the rest of the line unquoted (A1); `--stdin` takes a heredoc — preferred for text with quotes,
backticks, or newlines (A3). Text is stored VERBATIM; lines starting with `## `/`### ` are
refused (they would corrupt the heading scan).

**Output:** one confirmation line per write (`<slug>: <path> → R2 added (§4, you, …)`). Errors go
to stderr prefixed `pw-review:` with a `→ fix:` hint; exit `2` on usage/state errors
(unknown id, already-resolved item, bad decision word, missing section heading). Every
heading-changing operator reindexes `## Contents` and appends a LOG.md line automatically —
never re-run `pw-review.sh reindex` or `log` afterwards by hand.

**Lifecycle + gate reads** (merged from the old `pw-lib.sh review *` block — same semantics,
`review` prefix dropped): `init <slug> <review-rel> <doc-rel>` creates one review file
verbatim from the template (idempotent — never clobbers); `note-init <slug>` the
REVIEWER-NOTES.md header; `gate` prints the latest Sign-off decision (exit 0 iff approved);
`has-open` yes/no; `count` `open=N resolved=M items=K` (the ONE detector every display reads);
`reindex` rebuilds `## Contents`; `archive` moves fully-resolved blocks verbatim to the
`.archive.md` sibling with pointer rows (gate-safe); `reopen` appends a fresh in-review row
after a post-approval fix; `auto-signoff` is the mode=auto-only tool exception (re-checks the
config itself + zero open items, tags `pw-reviewer (auto)`, never a human row).

## pw-review.sh scan

Structured summary of every review file's item counts and sign-off state.

```bash
$PW_HOME/tooling/scripts/entities/pw-review.sh scan <slug>                  # all review files
$PW_HOME/tooling/scripts/entities/pw-review.sh scan <slug> --phase analysis # or: plan | task-plan | task-exec
```

**Output** — one line per review file, fields present only when non-zero:

```
analysis/topic.review.md: 2 open, 3 resolved (in-review)
task/review/PLAN.review.md: 5 resolved (approved)
task/review/PLAN.review.md: 5 resolved (approved)
task/review/T03.review.md: 1 open (in-review)
```

Trailing `(approved|in-review|changes-requested)` is the **last row of the file's Sign-off
table**. `No review files found` + exit `0` is a valid empty state (project too early for reviews).

Counts come from `pw-review.sh count <slug> <rel>` — the single heading-level detector the
gates use: template guidance text, worked examples inside comments, and UNFILLED `<…>` placeholder
stubs can never inflate them (2026-09-16 fix; see plan 15 §14).

**Reading failures:** exit `2` = usage error or missing project (`pw-review: …` on stderr).

**When to use:** instead of grepping `review/` yourself — `pw-status.sh` and `/pw-review`,
`/pw-close` pre-flights all call it. Filter with `--phase` when you only care about one lane.

## pw-context.sh

The context-doc entity. Human entry point: `/pw-context <slug> <operator> …`.

```bash
$PW_HOME/tooling/scripts/entities/pw-context.sh req-init <slug>
    # create context/REQUIREMENTS.md from context/_REQUIREMENTS.template.md (idempotent —
    # an existing brief is never touched). Prints the add-input reminder for its provenance row.

$PW_HOME/tooling/scripts/entities/pw-context.sh add-input <slug> --file <f> --what <w> --source <s> [--trust <t>]
    # append one row to context/INDEX.md's inputs table: | <f> | <w> | <s> | <today> | <t|—> |.
    # A2 flag-segment parsing is NATIVE: each value runs until the next --flag token, so
    # unquoted prose works ("--what Migration RFC excerpt --source Lark doc docs/xxxx").
    # The template's empty placeholder row is replaced by the first real row; `_e.g._`
    # example rows are never touched. "|" in values is escaped.

$PW_HOME/tooling/scripts/entities/pw-context.sh add-repo <slug> <repo> <base> <why…>
    # append one row to the "Repos in scope" table: | `<repo>` | `<base>` | <why> |.
    # A1 rest-of-line: everything after <base> is the why, unquoted.
    # NEVER touches /pw-adopt's <!-- pw-adopt-scope:… --> marker rows — appends below them.
```

**Output:** one confirmation line per write. Errors: stderr `pw-context:` + `→ fix:` hint, exit
`2` (missing flag value, missing INDEX.md, unknown operator). Rows are logged to LOG.md.

## pw-context.sh fetch

First pass over the provenance table in `context/INDEX.md`: for every row, reads column 1
("File / link" — a bare URL, a ticket key like `PAYMXMP-5702`, a filename, or a markdown link)
and fetches the **CLI-handleable** ones — Jira (`jira issue view`), GitHub issues/PRs (`gh`),
GitLab issues/MRs (`glab`). Local filenames and "Repos in scope" rows are skipped; rows no CLI
can take are printed for the agent, never as errors:

- Lark URLs → `Lark URL — agent handles via platform skill`
- web URLs / unfetched non-URLs without a CLI → `(no CLI fetched this — agent handles via WebFetch
  / platform skill)`

```bash
$PW_HOME/tooling/scripts/entities/pw-context.sh fetch <slug> [--ignore-errors]   # --ignore-errors mirrors
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

## pw-context.sh adopt-snapshot

For `/pw-adopt` on a repo that already has in-flight branches: snapshots the git state and
resolves the base branch (explicit MR target → forge lookup via `gh`/`glab` → repo default).

```bash
$PW_HOME/tooling/scripts/entities/pw-context.sh adopt-snapshot <slug> <repo> <branch> [mr-url]
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

## pw-mdlib.sh (source-only — not a command)

The shared markdown primitives both scripts (and `pw-lib.sh`) source: comment-blanked scanning
(the detector every review gate trusts), sign-off row reads, item-heading scans, and table
splice helpers. Never executed directly; if two scripts need the same document primitive, it
belongs here (S5).

## pw-context.sh adopt

The CONTINUATION workflow's record (was `pw-lib.sh adopt`): appends/upserts ONE unit per
`repo@branch` into `context/ADOPTED.md` (never clobbers earlier units — the bug free-form
editing caused), keeps `context/INDEX.md` in lockstep (one generic ADOPTED.md provenance row +
one hidden-marker-keyed row per unit in "Repos in scope"), and sets the dashboard `Adopted:`
pointer. `/pw-adopt` drives it once per adopted branch.

```bash
$PW_HOME/tooling/scripts/entities/pw-context.sh adopt <slug> <repo> <branch> <base> [mr-url]
```

Re-adopting the same `repo@branch` updates that unit's Base/MR lines in place; prose under the
unit is the agent's to fill, never the script's to touch.
