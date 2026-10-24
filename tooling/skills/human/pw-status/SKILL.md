---
name: pw-status
description: Show a project's phase, task status + open review items; update a verified task result, accept it, or advance to review; or with "rewind" move the dashboard Status back
args: "[rewind] --project <project-slug> [--phase <phase>] [--skip-cli-check] | --all [--attention] [--phase <phase>] [--json] | update --project <project-slug> (--task <T0n> --status complete|accepted | --status review)"
scope: mixed
scope-forms: "--all=global, default=project, rewind=project, update=project"
args-global: "--all [--attention] [--phase <phase>] [--json]"
args-project: "--project <project-slug> [--skip-cli-check] | rewind --project <project-slug> --phase <phase> | update --project <project-slug> (--task <T0n> --status complete|accepted | --status review)"
---

**Load shared guidance first.** Read the `pw-orchestration` skill's common rules
(`references/common.md`) before acting: authorization, operation scope, helper ownership, and
reporting. Load only the phase-specific references this operation needs. A read-only operation
must not run execution or mutation procedures.
Arguments: {{ARGS}}. Named-argument grammar: operator words first, every value named; the
project is always `--project <slug>`. Project dir: `{{PW_PROJECTS}}/<slug>`.

**Default flow — the status report:**

- **`/pw-status --project <slug> [--skip-cli-check]`** →
  `{{PW_HOME}}/tooling/scripts/entities/pw-status.sh --project <slug> [--skip-cli-check]` —
  the full status report (see the Deterministic pre-flight block below).

**Global overview — `--all` carries no project:**

- **`/pw-status --all [--attention] [--phase <phase>] [--json]`** →
  `{{PW_HOME}}/tooling/scripts/entities/pw-status.sh --all [--attention] [--phase <phase>] [--json]` —
  one row per discovered project: recorded phase, attention conditions, accepted tasks, last
  recorded workflow event, and the inspection command. Read-only: local records only — no forge,
  auth, model, or worker calls, and it never writes (it does not insert missing dashboard lines).
  `--attention` keeps only rows that need inspection; `--phase` filters by dashboard phase
  (`context|analysis|breakdown|executing|review|done`); `--json` prints one machine-readable
  object. Exit `1` = partial scan (unreadable or malformed records — rows are still shown with
  diagnostics); exit `2` = bad flags or an inaccessible projects root.

**If the operator word is `rewind`, this is the rewind flow, not a status report — skip
everything below and follow this instead** (`--phase` carries the phase to rewind to: `context` |
`analysis` | `breakdown` | `executing` | `review`):

- **`/pw-status rewind --project <slug> --phase <phase>`** → the guided rewind below (steps 1-4;
  the script call inside carries `--rewind`). Only ever on explicit human instruction.

1. Confirm the human actually wants this — going back a phase is a deliberate, visible move, not
   something to do on a hunch. Say what will change (current phase → target phase) and wait for a
   clear go-ahead before touching anything.
2. Record *why* on the target phase's review file first: a fresh `[OPEN]` item describing what
   needs to change, plus a new `in-review` Sign-off row (never delete the old `approved` row —
   it's history). If neither exists yet, tell me to add them first rather than rewinding into a
   phase with no record of *why*.
   - **Target `context` has an optional readiness record, but it gates nothing and must not replace
     this reopening record.** Record the reason on the existing downstream reviews instead: add one item to the analysis review
     (`/pw-review item --project <slug> --file analysis/review/<topic>.review.md --section <§anchor>
     --text what changed in context`) and, when `task/PLAN.md` exists, one to
     `task/review/PLAN.review.md`. That feedback reopens those approvals through the existing
     review machinery (history preserved; a stale approval can no longer be consumed). After the
     rewind, redo the context — `/pw-context prepare --project <slug> --brief <brief>` (or the
     manual row operators) — then re-run `/pw-analyze --project <slug>`; changed analysis or plans
     need fresh approvals.
3. Run `…/{{PW_HOME}}/tooling/scripts/entities/pw-status.sh status --project <slug> --phase <phase> --rewind` — this is
   the only place that flag is ever passed; a plain `status` call always refuses to move backward,
   by design.
4. Report the new phase and point me at the phase command to re-run (`/pw-analyze` / `/pw-breakdown`
   / …), then `/pw-review` to re-approve.

**If the operator word is `update`, this is the record-update flow — skip the report flow.**
One operator, three recognized values; every other value fails before any write.

- **`/pw-status update --project <slug> --task <T0n> --status complete`** — record a task that
  already ran and verified as `done`, without shipping. Requires phase `executing`, matching task
  file/PLAN status, a recorded `## Result` with a passing `Verify outcome:` and a commit or
  `zero-change` marker, and stable records during the check. It never re-runs the task, accepts it,
  pushes, or moves the phase. A real `verify-failed`, a bare `todo`, or contradicting holders blocks
  it; an already accepted task is a no-op. Before completing an `in-progress` task, confirm no
  executor is still writing it — the stable-read check catches a record that changes during the
  check, not a writer that has not reached it yet.
- **`/pw-status update --project <slug> --task <T0n> --status accepted`** — record my acceptance of
  the named result. The task must already be `done` in both holders, with recorded evidence, zero
  open items in `task/review/<T0n>.review.md`, and no active human rejection. Use this only after I
  say I accept that result. It does not merge, publish, or advance the phase.
- **`/pw-status update --project <slug> --status review`** — advance the whole project from
  `executing` to `review` when every PLAN task is `done`/`accepted` or blocked through a
  `verify-failed` dependency. It shares the execution readiness rule, logs one transition, and is a
  no-op when the project is already in review. Use `/pw-close` for project completion.
- **Unknown or combined input fails closed.** Values are case-sensitive and exactly `complete`,
  `accepted`, `review`. `--task` is required for the first two and rejected for `review`; `--phase`
  is rejected here (use the `rewind` flow or the owning phase command). Report the valid values and
  the correct selector; never substitute a nearby value, hand-edit a status line, or fall back to
  the internal setters.

After an update, report what changed in user terms: task and records affected, evidence used,
resulting phase, and any warning or partial write. Do not paste the internal invocation into a
user-facing plan or final summary unless I explicitly ask for technical details.

---

<!-- Pre-flight: deterministic status report (no agent needed) -->
```bash
{{PW_HOME}}/tooling/scripts/entities/pw-status.sh --project <slug>
```

The script produces the full status report (phase, task table, review items, AI Review modes,
LOG.md lines, blockers, next action, CLI auth status) — show it to the user as-is; `## Blockers`
is heuristic, so trust `pw-preflight.sh` over it for gate decisions. Exit 2 + `pw-status: …` =
bad slug / no such project. No agent invocation needed for report mode — only reason on top of
the report if the user asks a follow-up the fixed sections don't answer.
