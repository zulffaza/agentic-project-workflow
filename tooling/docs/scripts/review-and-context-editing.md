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
`pw-context fetch: N error(s):` with a per-row list; in `/pw-analyze` that's a STOP-and-ask.
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

The shared markdown primitives the entity scripts source: comment-blanked scanning
(the detector every review gate trusts), sign-off row reads, item-heading scans, and table
splice helpers. Never executed directly; if two scripts need the same document primitive, it
belongs here (S5).

Two table-cell writers with hard contracts:

- `_dashboard_update <file> <id-col> <target-col> <row-id> <value>` — the ONE dashboard-table
  cell writer (`dashboard-task-status`, `dashboard-mr-state`): resolves columns from the header
  by NAME (never positional — the MR table's State is column 5), rewrites exactly one cell, and
  fails loudly (`ERR: no row with ID=…`, file untouched) rather than no-op silently. **Fill rule
  (plan 23 / KI-2):** when no row matches but the table still carries an untouched template
  placeholder (a data row whose ID cell trims to empty — scaffold's `| | | | | |`), the FIRST
  such row is filled instead: ID ← row-id, target ← value, every other cell (including hint
  cells like `open / on-hold / merged`) preserved byte-for-byte. Only blank-ID rows can be
  placeholders — authored rows always carry an ID, so there is no clobber path.
- `_plan_cell_update <plan-file> <task-id> <col-name> <value>` — the ONE PLAN task-table cell
  writer (task-accept's Status sync, pw-config's pin propagator): `## Task` section, header
  cells mapped by NAME with the same normalization as `_pw_plan_map` (`status`, `executewith`),
  row matched by the `T0n` inside the ID cell (markdown links preserved), both PLAN generations,
  never positional; loud miss (section/column/row) with the file untouched.

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

## Verified gotchas — dated record owner (D2 routing)

This doc owns the settled records for the review/mdlib editing mechanisms (the user-facing
known-issues page was retired 2026-09-25 — [`../conventions.md`](../conventions.md) D-rules route
settled gotchas to the mechanism's own doc; user-reachable symptoms live in
[`docs/TROUBLESHOOTING.md`](../../../docs/TROUBLESHOOTING.md)). Each record: symptom, root cause,
the built-in mitigation, and a date — nothing shortened in the move.

### A review template's own format-hint text can permanently false-positive a naive "is anything open" check — *Mitigation (built in), 2026-08-10*
- **Symptom:** a plain `grep -qF '[OPEN]'` on any review file is *always* true, forever — even one
  with zero real open items.
- **Root cause:** `template/_REVIEW.template.md`'s permanent format-hint blockquote and its
  deletable worked-example block both contain the literal string `[OPEN]` as a syntax
  demonstration, by design — a naive whole-file grep can't tell that apart from a real item.
- **Mitigation (built in):** `_review_has_open_marker()` (`pw-mdlib.sh`) strips HTML comments
  first, then anchors only to real `### ` headings (not `> ` blockquote lines) — this is what the
  auto-signoff gate actually checks, and it's covered by the harness.
- Discovered during the AI-review feature's own testing, 2026-08-10.

### HTML comments cannot nest — a worked example living inside one needs bracket notation instead — *Mitigation (built in), 2026-08-10*
- **Symptom:** a real `<!-- pw-item-status: … -->` marker placed on a line inside
  `template/_REVIEW.template.md`'s WORKED-EXAMPLE block would prematurely close the *outer*
  `<!-- ↓↓ WORKED EXAMPLE … -->` comment at its own first `-->`, leaking the rest of the example
  into real, rendered content and exposing it to the gate check above.
- **Root cause:** HTML comments cannot nest — there is no way to open a second `<!--` while
  already inside one and have it behave as a distinct, independently-closable region.
- **Mitigation (built in):** every worked example in that template uses bracket notation
  (`[marker: pw-item-status open]`) instead of the real comment syntax, purely as a visual
  stand-in — never processed by tooling. The **live** headings outside any wrapping comment use
  the real syntax; only content already inside another comment needs the bracket substitute.
  Applies to both the Items and Open-questions worked examples — same reasoning either place.

### Status-marker TEXT in guidance prose = permanent phantom counts for every raw grep — *Mitigation (built in), 2026-09-16*
- **Symptom:** (`pw-status` "Unresolved review items") every review file reported "(1 open)"
  forever — even ones fully reviewed and resolved — and the review scan carried a dead `pending`
  counter on top.
- **Root cause:** three display paths counted with raw `grep -c "pw-item-status: open"`, which
  also matches the template's permanent `> **Add an item:** … <!-- pw-item-status: open -->`
  guidance line (prose on a `>` line, present in every review file) and unfilled R1/Q1 stub
  headings (which carry a REAL live marker by design, per the nesting record above, so
  copy-paste yields valid syntax). The gates used the shared heading-level detector and stayed
  correct — the display was just a fourth, un-blessed parser.
- **Mitigation (built in):** one detector serves everything: the review count read prints
  `open=N resolved=M items=K` off `_review_item_headings` (comment-blanked, `^###`-anchored,
  stubs filtered by their live `<YYYY-MM-DD`/`<§section>` placeholder tokens — BOTH tokens
  needed: live usage produced a half-cleaned stub that dropped only its timestamp). The review
  scan, the status report and the doc lint consume it; raw marker greps are banned;
  `auto-signoff` inherits the stub exemption (a clean pass must succeed).

### Existing projects keep pre-layout script paths in generated docs (harmless) — *informational, 2026-09*
- **Symptom:** a project scaffolded before the tooling-layout move has hint text naming the old
  flat paths / legacy catch-all script inside its README/review/template-derived files.
- **Impact:** none — those are inert documentation strings; the live flows call the entity
  scripts by their current paths (`tooling/scripts/{entities,lib,toolchain}/`). Re-bootstrap
  regenerates the commands; project docs can be refreshed opportunistically (or left — they
  still describe the right operators).

### Dashboard cell writers couldn't write into a still-empty table body (KI-2) — *Fixed 2026-09-25, mitigation built in*
- **Symptom (historical):** `dashboard-task-status` / `dashboard-mr-state` printed
  `ERR: no row with ID="T01" in the matched table` on a project whose README task table was still
  the template's empty `| | | | | |` placeholder — the update was skipped, so the dashboard
  silently drifted from the task files.
- **Root cause:** the row matcher required an existing data row; there was no "fill the first
  row" path for an untouched table.
- **Fix (built in):** `_dashboard_update`'s fill rule (contract above) fills the first untouched
  placeholder row — blank ID cell — preserving every other cell byte-for-byte; genuinely missing
  rows still fail loudly. Companion record: the `task-accept` half-sync (KI-1) lives in
  [`status-and-preflight.md`](./status-and-preflight.md).
