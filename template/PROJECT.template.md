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
- **AI Models:** <AI_MODELS_DEFAULT>
  <!-- 🤖 set via `/pw-config set --project {{PW_PROJECT_SLUG}} --key ai-model --set <role>=<provider:model>` — one row per spawn
       lane (researcher/analyst/writer-task/reviewer/verifier/ship-comment-analyst); `—` = no row = the provider's own
       default (kilo `small_model`/`subagent_model`; claude the session model; cursor the `auto`/
       `selectedModel` floor; codex its own configured default). The EXECUTOR is not
       a row — its pin is the task file's `Execute with:`/the PLAN's produced-by. Where a spawn
       can't bind the row (Kilo's Task-tool has no model arg), the driver runs the row as a headless
       session of that model over the same work order and the result says which actually ran.
       See docs/EXECUTION.md §Spawning phase work; set rows with `/pw-config set --project {{PW_PROJECT_SLUG}} --key ai-model --set <role>=<provider:model>`. -->
- **AI Review:** <AI_REVIEW_DEFAULT>
  <!-- 🤖 set via `/pw-config set --project {{PW_PROJECT_SLUG}} --key ai-review --set <surface>=<mode>` — one OUTCOME mode per review
       surface (context/analysis/plan/task-plan/task-exec/ship/rfc/close). `advisory` = a fresh
       pw-reviewer files items, a human still signs off; `auto` = it may also sign off itself on a
       genuinely clean pass (guarded tool call only). The removed `off` migrated to `advisory`
       (reads normalize; `/pw-config ensure --project {{PW_PROJECT_SLUG}}` persists it). Scheduling lives on the
       Review Trigger line, not here. See docs/REVIEW.md §3. -->
- **Review Trigger:** <REVIEW_TRIGGER_DEFAULT>
  <!-- 🤖 set via `/pw-config set --project {{PW_PROJECT_SLUG}} --key review-trigger --set <surface>=<value>` — `manual` = an AI pass
       starts only when you invoke one (`/pw-review ai --project {{PW_PROJECT_SLUG}} …`); `completion` = it also starts
       after a succeeded producing command's verification. `completion` never disables explicit
       requests. -->
- **Review Repair:** <REVIEW_REPAIR_DEFAULT>
  <!-- 🤖 set via `/pw-config set --project {{PW_PROJECT_SLUG}} --key review-repair --set <surface>=<value>` — `manual` = findings
       stop for you; `bounded` = a completion review may run the bounded cycle
       (review → repair → verify → fresh review) within the Review Budget. -->
- **Review Budget:** <REVIEW_BUDGET_DEFAULT>
- **AI Model Tuning:** <AI_MODEL_TUNING_DEFAULT>
  <!-- 🤖 machine-owned companion to AI Models. Kept on its own line so older readers of the
       role=model row keep working: `role=variant:x,reasoning:y,effort:z`. Empty = every lane uses
       its provider/session default tuning. Set with
       `/pw-config set --project {{PW_PROJECT_SLUG}} --key ai-model --set <role>=<provider:model> --variant <v> --reasoning <v> --effort <v>`.
       A binding is either honored exactly or refused; it is never silently downgraded. -->
- **Project Defaults:** <PROJECT_DEFAULTS_DEFAULT>
  <!-- 🤖 creation seed for PLAN-owned settings (`routing`, `execution-limit`, optional
       `max-parallel`). Captured when the project was created, so later global-default changes do
       NOT rewrite this project. Before task/PLAN.md exists, /pw-config show/get/set reads and
       updates these values (source: README Project Defaults, pending PLAN). /pw-breakdown copies
       them into PLAN once, then PLAN is authoritative and this line is creation history. -->
  <!-- 🤖 set via `/pw-config set --project {{PW_PROJECT_SLUG}} --key review-rounds --value <1..3>` — total reviewer passes in a
       bounded cycle; 3 allows at most two intervening verified repairs. -->


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
Filled once branches are pushed and MRs opened (see `/pw-ship`). Zero-change tasks have no
branch/MR — note that here rather than leaving a blank. `Build` reflects the terminal pipeline
result from ship/comment time (build-checking runs by default); it's `—` only when a run passed
`/pw-ship --skip-build-check`.

| Task | Repo | MR | Target branch | State | Build |
|------|------|----|--------------|-------|-------|
| | | | | open / on-hold / merged | — / green / red / still-running |

## Decisions & learnings (this project)  [🤖🧑 both]
Short running log — what we decided and why, what to do differently next time. This section is the
**always-available record**. If you've configured a memory tool (`PW_MEMORY` in `pw.config.sh`),
`/pw-close` also distils the durable bits into it; if not, they just live here.
- _e.g._ <2026-08-03 14:20> Chose Option A (feature flag) over a full migration — lower blast radius, reversible.
- <DD MMMM YYYY - HH.mm WIB> …
