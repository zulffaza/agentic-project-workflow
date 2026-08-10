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
  <!-- [🤖 set by /pw-analyze via `pw-lib.sh oneliner <slug> "…"`] — a one-sentence description
       distilled from context/. Leave the placeholder until analysis fills it. -->
- **AI Review:** <AI_REVIEW_DEFAULT>
  <!-- [🧑🤖 both] Optional, per-phase — off (default) | advisory | auto. Delegates a review pass to
       the pw-reviewer agent instead of (advisory) or in addition to (auto, if clean) a human.
       Change any phase any time: `pw-lib.sh ai-review <slug> <phase> <mode>` (phase: analysis |
       plan | task-plan | task-exec | ship). See docs/REVIEW.md. -->


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
- <YYYY-MM-DD HH:MM> …
