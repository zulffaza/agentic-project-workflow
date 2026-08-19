---
description: Show a project's phase, task status + open review items — or, with "rewind", move the dashboard Status back to an earlier phase
args: <project-slug> [rewind <phase>]
---
Arguments: {{ARGS}} (project slug). Project dir:
`{{PW_PROJECTS}}/<slug>`.

**If the 2nd argument is literally `rewind`, this is the rewind flow, not a status report — skip
everything below and follow this instead** (3rd argument is the phase to rewind to: `context` |
`analysis` | `breakdown` | `executing` | `review`):

1. Confirm the human actually wants this — going back a phase is a deliberate, visible move, not
   something to do on a hunch. Say what will change (current phase → target phase) and wait for a
   clear go-ahead before touching anything.
2. Check the target phase's review file has a fresh `[OPEN]` item describing what needs to change,
   and a new `in-review` Sign-off row (never delete the old `approved` row — it's history). If
   neither exists yet, tell me to add them first rather than rewinding into a phase with no record
   of *why*.
3. Run `…/{{PW_HOME}}/tooling/pw-lib.sh status <slug> <phase> --rewind` — this is the only place
   that flag is ever passed; a plain `status` call always refuses to move backward, by design.
4. Report the new phase and point me at the phase command to re-run (`/pw-analyze` / `/pw-breakdown`
   / …), then `/pw-review` to re-approve.

---

1. Show the current phase (`…/{{PW_HOME}}/tooling/pw-lib.sh phase <slug>`) and the task-status table
   from `README.md`, plus `task/PLAN.md`'s table (with SP/Time/Result) if present.
2. List artifacts with unresolved review items:
   ```bash
   grep -rln "pw-item-status: open" {{PW_PROJECTS}}/<slug>/
   ```
3. Show this project's AI Review modes (`…/{{PW_HOME}}/tooling/pw-lib.sh ai-review <slug>`) — only
   call this out if at least one phase isn't `off`. If `REVIEWER-NOTES.md` exists, show its most
   recent dated entry's header line (phase/artifact/mode/verdict), not the full file.
4. Show the last few `LOG.md` lines (recent activity).
5. Tell me what's blocking the next gate (unapproved analysis/plan, open reviews, or
   verify-failed tasks) and the single next action/command.
