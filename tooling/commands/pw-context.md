---
description: Deterministically edit the project's context docs — create the REQUIREMENTS.md brief from its template, add a provenance row to the context/INDEX.md inputs table, or add a repo to the "Repos in scope" table
args: <project-slug> <req-init | add-input | add-repo> …
---
Arguments: {{ARGS}}. Project dir: `{{PW_PROJECTS}}/<slug>`.

**This command is a mechanical mapping (C3): parse the arguments per the A-rules
(`{{PW_HOME}}/tooling/docs/conventions.md`), run the script verbatim, show its output. No
judgment, no doc reading, never hand-edit `context/INDEX.md` / `REQUIREMENTS.md` instead — the
script keeps the table shapes, dates, escaping, and `/pw-adopt` marker rows safe.**

The 2nd argument is the operator:

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

If an operator's script call fails, report its stderr line verbatim (it carries the `→ fix:`
hint) — do not retry by hand-editing the tables.
