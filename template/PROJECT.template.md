# <PROJECT_NAME>

<!-- This is the project DASHBOARD. Keep the status table current — it's how a resuming agent
     (or you, next week) picks up where things left off.
     Legend: 🤖 = AI-maintained (don't hand-edit) · 🧑 = you fill · 🤖🧑 = both. -->

- **Created:** <CREATED>
- **Status:** context
  <!-- 🤖 context → analysis → breakdown → executing → review → done. Each `/pw-*` command sets
       this as its last step — don't hand-edit except to match that vocabulary. -->
- **One-liner:** <what this project is>
  <!-- 🤖 set by /pw-analyze. Leave the placeholder until analysis fills it. -->
- **AI Review:** <AI_REVIEW_DEFAULT>
  <!-- 🤖 set via `/pw-review <slug> config <phase> <mode>` — off (default)/advisory/auto per
       phase. `/pw-review <slug> config` alone shows current settings. See docs/REVIEW.md. -->


## Where things are
- Context inputs → [`context/`](./context/INDEX.md)
- Analysis → [`analysis/`](./analysis/)  · reviews → [`analysis/review/`](./analysis/review/)
- Plan + tasks → [`task/PLAN.md`](./task/PLAN.md)  · reviews → [`task/review/`](./task/review/)
- Worktrees → [`worktree/`](./worktree/)
- RFC doc (optional, appears after the first `/pw-rfc` run) → [`rfc/RFC.md`](./rfc/RFC.md)
- Activity log (audit trail) → [`LOG.md`](./LOG.md)

Full workflow guide: `../agentic-project-workflow/README.md`.

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
Short running log — what we decided and why, what to do differently next time. This section is the
**always-available record**. If you've configured a memory tool (`PW_MEMORY` in `pw.config.sh`),
`/pw-close` also distils the durable bits into it; if not, they just live here.
- _e.g._ <2026-08-03 14:20> Chose Option A (feature flag) over a full migration — lower blast radius, reversible.
- <YYYY-MM-DD HH:MM> …
