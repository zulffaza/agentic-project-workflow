---
description: Deterministically edit the project's context docs — create the REQUIREMENTS.md brief, add a provenance row or repo row — or let the agent prepare reviewable context from your stated intent
args: <project-slug> <req-init | add-input | add-repo | prepare> …
---
Arguments: {{ARGS}}. Project dir: `{{PW_PROJECTS}}/<slug>`.

**Operator split — get this right.** The row operators are a mechanical mapping (C3).
`req-init`, `add-input`, and `add-repo` parse the arguments per the A-rules
(`{{PW_HOME}}/tooling/docs/conventions.md`), run the script verbatim, and show its output — no
judgment, no doc reading, never hand-edit `context/INDEX.md` / `REQUIREMENTS.md` instead; the
script keeps the table shapes, dates, escaping, and `/pw-adopt` marker rows safe. **`prepare` is
the one reasoning operator on this command**: it loads the `project-workflow` skill's
`references/context.md` and follows that contract; it still writes every table and workflow-state
change through the entity helpers, and it stops before analysis.

The 2nd argument is the operator:

- **`/pw-context <slug> prepare [free-form brief]`** — assisted preparation for an existing
  project: turn my request into reviewable context (requirements draft, traceable inputs,
  evidence-backed repository guesses). In order:
  1. **Phase gate first — before any write.** Run
     `{{PW_HOME}}/tooling/scripts/entities/pw-preflight.sh prepare <slug>`; non-zero = STOP and
     relay its `→ fix:` (a project that moved on needs `/pw-status <slug> rewind context`, with
     the affected analysis/PLAN reviews reopened first). Change nothing before the gate passes.
  2. Load the `project-workflow` skill's `references/context.md` and run its preparation flow:
     read the dashboard, context index, existing brief, and relevant inputs; draft the existing
     requirements sections — separate my stated requirements, source-backed constraints, and
     agent suggestions; gather sources once; record supported repository guesses.
  3. Save through the entity helpers only — `req-init` (missing brief), `ensure-input` /
     `ensure-repo` (keyed: a repeat run updates rows in place and never duplicates them), and one
     preparation record via the status/log helper. Preserve user edits and `/pw-adopt` records.
  4. Verify the saved context, then reply with the brief + index links, the unresolved decisions,
     source gaps, and the next action (`/pw-analyze <slug>` when the draft is usable). **Stop
     before analysis** — no analysis, no approval, no automatic `/pw-analyze`.
  An omitted brief means resume from the saved context and this conversation; if both are empty,
  ask me for the intended outcome before constructing requirements.

- **`/pw-context <slug> req-init`** → `{{PW_HOME}}/tooling/scripts/entities/pw-context.sh req-init <slug>` —
  creates `context/REQUIREMENTS.md` from its template (idempotent; an existing brief is never
  touched). Afterwards, remind me to fill it in and add its provenance row with `add-input`.

- **`/pw-context <slug> add-input --file <f> --what <prose…> --source <prose…> [--trust <prose…>]`**
  → pass the flags through to `{{PW_HOME}}/tooling/scripts/entities/pw-context.sh add-input <slug> …` exactly as
  typed (A2 flag-segment form: each value runs until the next `--flag` token — the script parses
  this natively, so hand the whole tail over verbatim; shell-quote each segment when composing the
  command). Appends one row to the INDEX inputs table with today's date; `--trust` defaults to `—`.

- **`/pw-context <slug> add-repo <repo> <base> <why…>`** → `{{PW_HOME}}/tooling/scripts/entities/pw-context.sh
  add-repo <slug> <repo> <base> <why…>` (A1: everything after `<base>` is the why, unquoted —
  pass the rest of my line through verbatim). Appends one row to the "Repos in scope" table.
  Never touches `/pw-adopt`'s marker rows.

If an operator's script call fails: keep its stderr verbatim in your working context (the
`→ fix:` line names the recovery), and make your final reply state the cause, the affected file,
and the recovery as a `/pw-*` action — quote the raw error line too when it carries evidence.
Do not retry by hand-editing the tables, and never present a failed run as success.
