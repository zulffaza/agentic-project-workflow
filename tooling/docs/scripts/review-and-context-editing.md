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
$PW_HOME/tooling/scripts/entities/pw-review.sh init <slug> <review-rel> <doc-rel>    # legacy single-file triple (kept)
$PW_HOME/tooling/scripts/entities/pw-review.sh init-docs <slug> <artifact-rel> [<artifact-rel>…]
    # review files for EXACTLY the named artifacts (one is a valid list). The full list is
    # VALIDATED FIRST — missing docs, template/README targets, unsupported artifacts, and
    # out-of-project paths reject everything and create nothing; paths normalize + dedupe,
    # quoted paths with spaces survive. No scan for extra targets: earlier- or later-phase
    # reviews never appear as a side effect, and selecting an earlier-phase artifact creates
    # ONLY its file (no gate reopen, no repair). Idempotent: a rerun finishes missing files
    # without replacing existing review content or history; a later per-file write failure
    # reports created / skipped / failed targets separately.
$PW_HOME/tooling/scripts/entities/pw-review.sh init-all <slug>
    # creates the missing review files for the project's ACTUAL CURRENT dashboard phase — read
    # from the dashboard Status: at invocation, never inferred from which dirs hold files:
    #   context    → nothing implicit (explain the context commands)
    #   analysis   → analysis-topic artifacts only (RFC staging stays its own explicit side-loop)
    #   breakdown  → PLAN + current task-plan artifacts, per the existing optional per-task policy
    #   executing / review → current task-result artifacts; never analysis reviews here
    #   done       → no implicit mutation; require an explicit artifact (init-docs) or a rewind
    # No user phase override, no project-wide fallback: a missing/unknown dashboard phase
    # stops with a command-based recovery hint. Never creates earlier/later-phase reviews and
    # never deletes previously generated ones; existing files untouched.

$PW_HOME/tooling/scripts/entities/pw-review.sh start <slug> <review-rel> [--phase <analysis|plan|task-plan|task-exec|ship>] [--provider <actual-provider>] [--model <actual-model>] [--confirm-earlier]
    # pass-entry transition: appends ONE changes-requested row before the work set, and ONLY
    # when this file genuinely has eligible work — a real actionable OPEN item, or an answered
    # question awaiting incorporation. Template stubs, resolved/archived rows, settled
    # questions, malformed-only entries, waiting-human-only pending questions, and out-of-scope
    # asks append NOTHING (signoff state preserved; report what was skipped). Per artifact:
    # working one selected file never changes another file's signoff. The work set is
    # re-checked under the per-file lock immediately before publishing the row.
    # No --phase        → normal repair pass, By pw-review (repair).
    # With --phase      → independent AI pass under that lane's configured advisory|auto mode,
    #                     By pw-reviewer (<mode>; provider=<actual>; model=<actual>) — identity
    #                     read from the actual run metadata, never the config pin, the
    #                     orchestrator, or the artifact author; unconfirmed identity is
    #                     recorded as unknown, and a reviewer change on retry is a distinct
    #                     attempt, not a reuse of the old attribution.
    # Retry/resume of the same active pass appends no duplicate; later internal item writes
    # inside an active pass never toggle the state back. If the artifact's phase is EARLIER
    # than the current dashboard phase, --confirm-earlier is required: without it the gate is
    # left untouched (the feedback itself can still be recorded; its open state blocks the
    # next phase from consuming the stale approval). start can NEVER write approved.
$PW_HOME/tooling/scripts/entities/pw-review.sh signoff <slug> <review-rel-path> <decision> [--by <name>]
    # append a Sign-off row: decision ∈ approved | changes-requested | in-review.
    # HUMAN-TRIGGERED ONLY (C4) — an agent runs this only verbatim on the user's explicit
    # instruction, never on its own initiative, and the row stays attributed to the human
    # (--by only names the person the user asked for); the agent-side gate path is
    # pw-review.sh auto-signoff and agent operational transitions are start / the item and
    # answer writers — never this operator.
    # Append-only: existing rows are history and are never edited or deleted. The first
    # sign-off replaces the template's lone "| | | in-review |" placeholder row.

$PW_HOME/tooling/scripts/entities/pw-review.sh add-item <slug> <review-rel-path> --section <§anchor> (--text <ask…> | --stdin) [--actor <name>]
    # append the next Rn block at the end of ## Items: heading + timestamp + (actor,…) +
    # <!-- pw-item-status: open --> marker + body + --- rule, then reindex ## Contents.
    # Fills the template's unfilled R-stub in place (no phantom duplicate R1).
    # Ids stay monotonic across archives (archived <!-- pw-archived:Rn --> markers counted).
    # --actor defaults to "you"; only pw-review/pw-reviewer surfaces pass --actor "pw-reviewer".
    # A successful FIRST real item on a blank/changes-requested/approved file also appends one
    # attributed `pw-review (feedback)` `in-review` row in the same validated per-file write —
    # there is no visible interval with new feedback and a still-consumable stale approval.
    # Repeated feedback inside an already-queued `in-review` cycle adds no row, and writes
    # belonging to an active pass (the writer is the pass itself) never toggle its state.

$PW_HOME/tooling/scripts/entities/pw-review.sh answer <slug> <review-rel-path> <Qid> (--text <answer…> | --stdin)
    # append your "> ↳ **you** (<now>): …" line under question Qid — same quoted block, blank
    # quoted ">" separator between consecutive ↳ lines. Refuses missing/[ANSWERED] questions.
    # Does NOT flip the status: the agent folds the answer into the doc and flips it (doctrine).
    # A first answer after an approval triggers the same `pw-review (feedback)` `in-review` row
    # a new item does; later answers in the queued cycle add none.

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
`review` prefix dropped): `init <slug> <review-rel> <doc-rel>` (legacy triple, kept for
mechanical callers) and `init-docs <slug> <artifact-rel>…` (validated selected list) create
review files verbatim from the template (idempotent — never clobbers); `init-all <slug>` does
the current dashboard phase only; `note-init <slug>` the REVIEWER-NOTES.md header; `gate`
prints the latest meaningful Sign-off decision (exit 0 iff that approval is CONSUMABLE: the latest
row reads approved — either legacy decoration included — **and** no real unresolved item remains
**and** no explicit human `changes-requested` is still standing; a blocked-but-approved state
prints the reason on stderr and exits 1; an unknown or malformed table fails closed with a
command-based repair hint — it is never treated as blank). Displays (scan/status/help) additionally
show the decision's actor; `gate` itself prints the decision token; `has-open` yes/no; `count`
`open=N resolved=M items=K` (the ONE detector every display reads); `reindex` rebuilds
`## Contents`; `archive` moves fully-resolved blocks verbatim to the `.archive.md` sibling with
pointer rows (gate-safe); `reopen` appends a workflow-attributed fresh in-review row when a fix
lands on an approved file whose own queue has no startable work set (the cross-file case — an
RFC-routed fix; the legacy `pw-review (auto-reopen)` rows stay readable); `start` is the
pass-entry transition (above); `auto-signoff` is the mode=auto-only tool exception — it
re-checks the config itself, zero open items in that file, artifact/lane match, and no standing
explicit human rejection, tags `pw-reviewer (auto; provider=<actual>; model=<actual>)` from the
actual run metadata (`unknown` when unconfirmed), never a human row, and honors
`--confirm-earlier` for an earlier-phase gate like start does. Approval discovery never reads
`analysis/review/RFC.review.md`'s table: the RFC staging file gates nothing on its own; its
unresolved comments block the consuming command through `has-open` (a fix routed from RFC
feedback acts on the analysis document's OWN review gate).

**Handoff operators (advisory external reports).** `prepare <slug> <scope> [--refresh] [--repair]
[--pass-id <id>] [--print]` freezes ONE review unit into `review/ai/<pass-id>/` — `manifest.json`
(surface, artifact, round/budget, reviewed-identity `fingerprint`, recorded inputs/code evidence,
existing-item ledger, state), a byte-identical `snapshot/` of the reviewed inputs, and a neutral
`request.md` — WITHOUT launching any model; an existing packet for the same unit is shown, never
overwritten, and `--repair` is refused past the README's `Review Budget` rounds.
`import <slug> --report <file.json> [--pass <id>]` validates ONE external report against its
prepared manifest (schema `pw-review-report/1`, project/pass binding, freshness fingerprint —
content inputs AND recorded worktree head/patch digest for task surfaces) and files its
findings/questions through the same item/question writers, credited `pw-reviewer (external)`;
replay-safe (progress recorded per item; an identical replay is a no-op, one report per pass), and
ADVISORY ONLY — no pass row, no approval, no repair, no `auto-signoff`, regardless of the surface's
outcome mode. `passes` (read facet) lists every packet by pass-id/surface/state/artifact/round/
verdict. The new surfaces `context` (→ `context/review/CONTEXT.review.md`), `rfc` content (→
`rfc/review/RFC-CONTENT.review.md`, distinct from the comment staging) and `close` (→
`review/CLOSE.review.md`) join the lane map; RFC staging keeps matching no surface.

**Sign-off actors (attribution contract).** One append-only table, five distinct `By` values —
the actor names WHO decided, not what physically wrote the row:

| Source of the row | `By` value | Decisions it may hold |
|---|---|---|
| Explicit human signoff request | `you`, or the named human | `in-review` · `changes-requested` · `approved` |
| Automatic transition after human feedback | `pw-review (feedback)` | `in-review` |
| Normal agent repair pass | `pw-review (repair)` | `changes-requested` (validated nonempty work only) |
| Independent AI pass, advisory mode | `pw-reviewer (advisory; provider=<p>; model=<m>)` | `changes-requested` with real findings; NEVER `approved` |
| Independent AI pass, auto mode | `pw-reviewer (auto; provider=<p>; model=<m>)` | `changes-requested` with real findings; `approved` only via the guarded auto-signoff |

External report imports write item/question headings credited `(pw-reviewer (external), <ts>)`
(classified as the reviewer role, never a human) and write NO decision row of their own — their
provenance lives in the pass manifest, the validated `report.json` copy, and one `REVIEWER-NOTES.md`
entry (`mode=external`, `ADVISORY ONLY`).

Gate evaluation reads the decision, the artifact role, and the configured approval policy — never
a substring of the actor label. Readers must tell human rows from recognized automated actors
when applying the human-rejection rule: an explicit human `changes-requested` is only cleared by
an explicit human `in-review`/`approved`, never by an operational row. Legacy `you`, named-human,
`pw-review (auto-reopen)`, and plain `pw-reviewer (auto)` rows stay valid history — readers parse
the reviewer role + mode with or without identity fields, richer `By` values never break decision
parsing, and idempotency suppresses duplicates only within the same attempt. Review timestamps:
new rows stamp `5 October 2026 23.11 WIB` (day, month, year, dot-minutes); older date-time
formats already in files are accepted unchanged. New template stubs use
`<DD MMMM YYYY - HH.mm WIB>`; every stub filter accepts both that token and legacy
`<YYYY-MM-DD HH:MM>`/`<§section>` tokens. Status/help/scan displays all show the same latest
decision together with its `By` actor, read through one shared latest-row reader.

## pw-review-read.sh

Structured summary of every review file's item counts and sign-off state.
The read facet owns `gate`, `has-open`, `count`, `eligible`, `scan`, and `passes`
(the prepare/import packet inventory).
Legacy `pw-review.sh` read calls forward here with their argument shapes preserved.

```bash
$PW_HOME/tooling/scripts/entities/pw-review-read.sh scan <slug>                  # all review files
$PW_HOME/tooling/scripts/entities/pw-review-read.sh scan <slug> --phase analysis # or: plan | task-plan | task-exec | ship
```

`--phase` names are **review lanes**, not dashboard phases: `task-plan` resolves to the task
artifacts, `ship` to their mirrored task reviews, `plan` to PLAN files, `analysis` to
analysis-topic reviews. RFC staging files are never surfaced as approval rows.

**Output** — one line per review file, fields present only when non-zero:

```
analysis/topic.review.md: 2 open, 3 resolved (in-review · pw-review (feedback))
task/review/PLAN.review.md: 5 resolved (approved · you)
task/review/T03.review.md: 1 open (changes-requested · pw-review (repair))
```

The trailing pair is the **latest meaningful row of the file's Sign-off table** — decision and
its `By` actor together — read through the shared latest-row reader, so a hyphenated decision
(`changes-requested`) is never split at a dash and legacy rows (no identity fields, old date
formats, `approved` with the legacy checkmark) display exactly as recorded. A blank/placeholder
latest state shows as unapproved. `No review files found` + exit `0` is a valid empty state
(project too early for reviews).

Counts come from `pw-review-read.sh count <slug> <rel>` — the single heading-level detector the
gates use: template guidance text, worked examples inside comments, and UNFILLED `<…>` placeholder
stubs can never inflate them (2026-09-16 fix).

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

$PW_HOME/tooling/scripts/entities/pw-context.sh ensure-input <slug> --file <f> --what <w> --source <s> [--trust <t>]
    # keyed upsert for the inputs table — assisted preparation's repeat-run path (/pw-context
    # <slug> prepare): identity = the normalized "File / link" cell (trim, one surrounding
    # backtick pair, \| unescape, whitespace collapse — URL query parameters and case
    # preserved). No row → append; one row → update what/source/trust in place keeping the
    # original date; identical content → no write at all; duplicate rows that disagree →
    # conflict report, nothing written. Phase context only.

$PW_HOME/tooling/scripts/entities/pw-context.sh ensure-repo <slug> <repo> <base> <why…>
    # keyed upsert for the "Repos in scope" table: identity = normalized (repo, base). No row
    # → append; one row → update the why in place; identical → no write. The same repo on a
    # DIFFERENT base stays a separate row; /pw-adopt marker rows are never touched. Duplicate
    # disagreement stops with a conflict. Phase context only.
```

**Output:** one confirmation line per write (`added` / `updated` / `already present
(unchanged)`). Errors: stderr `pw-context:` + `→ fix:` hint, exit
`2` (missing flag value, missing INDEX.md, unknown operator, preparation outside phase context,
duplicate-row conflict). Rows are logged to LOG.md.

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
  (built in 2026-09-25):** when no row matches but the table still carries an untouched template
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
  stubs filtered by their live `<DD MMMM YYYY`, legacy `<YYYY-MM-DD`, and `<§section>` placeholder tokens — timestamp and section tokens
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

### Dashboard cell writers couldn't write into a still-empty table body — *Fixed 2026-09-25, mitigation built in*
- **Symptom (historical):** `dashboard-task-status` / `dashboard-mr-state` printed
  `ERR: no row with ID="T01" in the matched table` on a project whose README task table was still
  the template's empty `| | | | | |` placeholder — the update was skipped, so the dashboard
  silently drifted from the task files.
- **Root cause:** the row matcher required an existing data row; there was no "fill the first
  row" path for an untouched table.
- **Fix (built in):** `_dashboard_update`'s fill rule (contract above) fills the first untouched
  placeholder row — blank ID cell — preserving every other cell byte-for-byte; genuinely missing
  rows still fail loudly. Companion record: the `task-accept` half-sync lives in
  [`status-and-preflight.md`](./status-and-preflight.md).
