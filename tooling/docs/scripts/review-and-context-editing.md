# Review and context editing scripts

Deterministic writes to the two human-edited document families: review files
(`pw-review-edit.sh`) and the context docs (`pw-context.sh`). Both exist so nobody hand-copies
template blocks or hand-matches house style — every heading, marker, timestamp, `---` rule,
table row, and reindex is written by the script. Placement rules for these (and any future)
scripts/operators: [`../conventions.md`](../conventions.md).

## pw-review-edit.sh

The review-doc entity's write side (read side stays `pw-review-scan.sh` / `pw-lib.sh review
gate|count|has-open`). Human entry point: `/pw-review <slug> <operator> …`.

```bash
$PW_HOME/tooling/pw-review-edit.sh init-all <slug>
    # create every missing review file: analysis/<topic>.md, task/PLAN.md, each task/T0n.md
    # → sibling review/<name>.review.md (via pw-lib.sh review-init). Idempotent; exit 0 always.

$PW_HOME/tooling/pw-review-edit.sh signoff <slug> <review-rel-path> <decision> [--by <name>]
    # append a Sign-off row: decision ∈ approved | changes-requested | in-review.
    # HUMAN-TRIGGERED ONLY (C4) — an agent runs this only verbatim on the user's explicit
    # instruction, never on its own initiative; the agent-side path is
    # pw-lib.sh review auto-signoff (mode=auto + zero open items only).
    # Append-only: existing rows are history and are never edited or deleted. The first
    # sign-off replaces the template's lone "| | | in-review |" placeholder row.

$PW_HOME/tooling/pw-review-edit.sh add-item <slug> <review-rel-path> --section <§anchor> (--text <ask…> | --stdin) [--actor <name>]
    # append the next Rn block at the end of ## Items: heading + timestamp + (actor,…) +
    # <!-- pw-item-status: open --> marker + body + --- rule, then reindex ## Contents.
    # Fills the template's unfilled R-stub in place (no phantom duplicate R1).
    # Ids stay monotonic across archives (archived <!-- pw-archived:Rn --> markers counted).
    # --actor defaults to "you"; only pw-review/pw-reviewer surfaces pass --actor "pw-reviewer".

$PW_HOME/tooling/pw-review-edit.sh answer <slug> <review-rel-path> <Qid> (--text <answer…> | --stdin)
    # append your "> ↳ **you** (<now>): …" line under question Qid — same quoted block, blank
    # quoted ">" separator between consecutive ↳ lines. Refuses missing/[ANSWERED] questions.
    # Does NOT flip the status: the agent folds the answer into the doc and flips it (doctrine).

$PW_HOME/tooling/pw-review-edit.sh add-question <slug> <review-rel-path> --section <§anchor> (--text <q…> | --stdin) [--actor <name>]
    # agent-side: append the next Qn block ([PENDING] + open marker) at the end of
    # ## Open questions, then reindex. Fills the template's Q-stub in place.

$PW_HOME/tooling/pw-review-edit.sh resolve <slug> <review-rel-path> <Rid|Qid> (--reply <text…> | --stdin)
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
to stderr prefixed `pw-review-edit:` with a `→ fix:` hint; exit `2` on usage/state errors
(unknown id, already-resolved item, bad decision word, missing section heading). Every
heading-changing operator reindexes `## Contents` and appends a LOG.md line automatically —
never re-run `pw-lib.sh review reindex` or `log` afterwards by hand.

## pw-context.sh

The context-doc entity. Human entry point: `/pw-context <slug> <operator> …`.

```bash
$PW_HOME/tooling/pw-context.sh req-init <slug>
    # create context/REQUIREMENTS.md from context/_REQUIREMENTS.template.md (idempotent —
    # an existing brief is never touched). Prints the add-input reminder for its provenance row.

$PW_HOME/tooling/pw-context.sh add-input <slug> --file <f> --what <w> --source <s> [--trust <t>]
    # append one row to context/INDEX.md's inputs table: | <f> | <w> | <s> | <today> | <t|—> |.
    # A2 flag-segment parsing is NATIVE: each value runs until the next --flag token, so
    # unquoted prose works ("--what Migration RFC excerpt --source Lark doc docs/xxxx").
    # The template's empty placeholder row is replaced by the first real row; `_e.g._`
    # example rows are never touched. "|" in values is escaped.

$PW_HOME/tooling/pw-context.sh add-repo <slug> <repo> <base> <why…>
    # append one row to the "Repos in scope" table: | `<repo>` | `<base>` | <why> |.
    # A1 rest-of-line: everything after <base> is the why, unquoted.
    # NEVER touches /pw-adopt's <!-- pw-adopt-scope:… --> marker rows — appends below them.
```

**Output:** one confirmation line per write. Errors: stderr `pw-context:` + `→ fix:` hint, exit
`2` (missing flag value, missing INDEX.md, unknown operator). Rows are logged to LOG.md.

## pw-mdlib.sh (source-only — not a command)

The shared markdown primitives both scripts (and `pw-lib.sh`) source: comment-blanked scanning
(the detector every review gate trusts), sign-off row reads, item-heading scans, and table
splice helpers. Never executed directly; if two scripts need the same document primitive, it
belongs here (S5).
