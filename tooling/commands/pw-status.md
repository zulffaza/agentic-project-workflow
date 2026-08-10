---
description: Show a project's phase, task status + open review items
args: <project-slug>
---
Arguments: {{ARGS}} (project slug). Project dir:
`{{PW_PROJECTS}}/<slug>`.

1. Show the current phase (`…/{{PW_HOME}}/tooling/pw-lib.sh phase <slug>`) and the task-status table
   from `README.md`, plus `task/PLAN.md`'s table (with SP/Time/Result) if present.
2. List artifacts with unresolved review items:
   ```bash
   grep -rln "🔴 open" {{PW_PROJECTS}}/<slug>/
   ```
3. Show this project's AI Review modes (`…/{{PW_HOME}}/tooling/pw-lib.sh ai-review <slug>`) — only
   call this out if at least one phase isn't `off`. If `REVIEWER-NOTES.md` exists, show its most
   recent dated entry's header line (phase/artifact/mode/verdict), not the full file.
4. Show the last few `LOG.md` lines (recent activity).
5. Tell me what's blocking the next gate (unapproved analysis/plan, open reviews, or
   verify-failed tasks) and the single next action/command.
