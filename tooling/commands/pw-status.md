---
description: Show a project's phase, task status + open review items — or, with "rewind", move the dashboard Status back to an earlier phase
args: <project-slug> [rewind <phase>] | --all [--attention] [--phase <phase>] [--json]
---
Arguments: {{ARGS}} (project slug). Project dir:
`{{PW_PROJECTS}}/<slug>`.

**No-slug overview:** when the 1st argument is literally `--all`, there is no `<project-slug>` —
that form is the read-only cross-project overview:

- **`/pw-status --all [--attention] [--phase <phase>] [--json]`** →
  `{{PW_HOME}}/tooling/scripts/entities/pw-status.sh --all [--attention] [--phase <phase>] [--json]` —
  one row per discovered project: recorded phase, attention conditions, accepted tasks, last
  recorded workflow event, and the inspection command. Read-only: local records only — no forge,
  auth, model, or worker calls, and it never writes (it does not insert missing dashboard lines).
  `--attention` keeps only rows that need inspection; `--phase` filters by dashboard phase
  (`context|analysis|breakdown|executing|review|done`); `--json` prints one machine-readable
  object. Exit `1` = partial scan (unreadable or malformed records — rows are still shown with
  diagnostics); exit `2` = bad flags or an inaccessible projects root.

**If the 2nd argument is literally `rewind`, this is the rewind flow, not a status report — skip
everything below and follow this instead** (3rd argument is the phase to rewind to: `context` |
`analysis` | `breakdown` | `executing` | `review`):

1. Confirm the human actually wants this — going back a phase is a deliberate, visible move, not
   something to do on a hunch. Say what will change (current phase → target phase) and wait for a
   clear go-ahead before touching anything.
2. Record *why* on the target phase's review file first: a fresh `[OPEN]` item describing what
   needs to change, plus a new `in-review` Sign-off row (never delete the old `approved` row —
   it's history). If neither exists yet, tell me to add them first rather than rewinding into a
   phase with no record of *why*.
   - **Target `context` has no context review file of its own — never create one.** Record the
     reason on the existing downstream reviews instead: add one item to the analysis review
     (`/pw-review <slug> item analysis/review/<topic>.review.md --section <§anchor> --text what
     changed in context`) and, when `task/PLAN.md` exists, one to `task/review/PLAN.review.md`.
     That feedback reopens those approvals through the existing review machinery (history
     preserved; a stale approval can no longer be consumed). After the rewind, redo the context —
     `/pw-context <slug> prepare <brief>` (or the manual row operators) — then re-run
     `/pw-analyze <slug>`; changed analysis or plans need fresh approvals.
3. Run `…/{{PW_HOME}}/tooling/scripts/entities/pw-status.sh status <slug> <phase> --rewind` — this is the only place
   that flag is ever passed; a plain `status` call always refuses to move backward, by design.
4. Report the new phase and point me at the phase command to re-run (`/pw-analyze` / `/pw-breakdown`
   / …), then `/pw-review` to re-approve.

---

<!-- Pre-flight: deterministic status report (no agent needed) -->
```bash
{{PW_HOME}}/tooling/scripts/entities/pw-status.sh <slug>
```

The script produces the full status report (phase, task table, review items, AI Review modes,
LOG.md lines, blockers, next action, CLI auth status) — show it to the user as-is; `## Blockers`
is heuristic, so trust `pw-preflight.sh` over it for gate decisions. Exit 2 + `pw-status: …` =
bad slug / no such project. No agent invocation needed for report mode — only reason on top of
the report if the user asks a follow-up the fixed sections don't answer.
