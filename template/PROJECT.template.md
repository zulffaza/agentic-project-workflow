# <PROJECT_NAME>

<!-- This is the project DASHBOARD. Keep the status table current — it's how a resuming agent
     (or you, next week) picks up where things left off.
     Legend: 🤖 = AI-maintained (don't hand-edit) · 🧑 = you fill · 🤖🧑 = both. -->

- **Created:** <CREATED>
- **Status:** context
  <!-- Lifecycle: context → analysis → breakdown → executing → review → done.
       The `/pw-*` commands OWN this transition — each command sets it as its last step
       (pw-analyze→analysis, pw-breakdown→breakdown, pw-execute→executing then review,
       pw-close→done). If you edit it by hand, keep to that vocabulary. -->
- **One-liner:** <what this project is>

## Where things are
- Context inputs → [`context/`](./context/INDEX.md)
- Analysis → [`analysis/`](./analysis/)  · reviews → [`analysis/review/`](./analysis/review/)
- Plan + tasks → [`task/PLAN.md`](./task/PLAN.md)  · reviews → [`task/review/`](./task/review/)
- Worktrees → [`worktree/`](./worktree/)
- Activity log (audit trail) → [`LOG.md`](./LOG.md)

Full workflow guide: `../base/README.md`.

## Task status  [🤖 agent-maintained]
Mirror of `task/PLAN.md` for at-a-glance progress (agents keep it current; you only ever flip a
task to `accepted`/`verify-failed`). Per-task SP, timing + commit/MR outcome live in
`task/PLAN.md`'s task table; this is the quick view.

| ID | Title | Repo | Status | Notes |
|----|-------|------|--------|-------|
| | | | | |

_todo → in-progress → verify-failed / done → accepted_

## Merge requests  [🤖 agent-maintained]
Filled during execution once branches are pushed and MRs opened (see `/pw-execute`). Zero-change
tasks have no branch/MR — note that here rather than leaving a blank.

| Task | Repo | MR | Target branch | State |
|------|------|----|--------------|-------|
| | | | | open / on-hold / merged |

## Decisions & learnings (this project)  [🤖🧑 both]
Short running log — what we decided and why, what to do differently next time. Distil the durable
bits into EverOS `personal` memory at close-out (`/pw-close`).
- <YYYY-MM-DD HH:MM> …
