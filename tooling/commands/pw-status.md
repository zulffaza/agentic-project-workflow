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
   rtk grep -rln "🔴 open" {{PW_PROJECTS}}/<slug>/
   ```
3. Show the last few `LOG.md` lines (recent activity).
4. Tell me what's blocking the next gate (unapproved analysis/plan, open reviews, or
   verify-failed tasks) and the single next action/command.
