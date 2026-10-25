---
name: pw-orchestration
description: Shared orchestration rules for every project-workflow operation in the normal session — authorization, operation scope, helper ownership, worker handoffs, checkpoints, repair coordination, and reporting. Use whenever a /pw-* entry point or a plain-language PW request starts. Read references/common.md first; load only the phase-specific reference the operation needs. Never selects a primary agent, changes permissions, approves a gate, or publishes.
---

# pw-orchestration (normal-session driver)

Portable driver rules for the project-workflow bundle. The human starts an operation through a
`/pw-*` entry point (or an explicit plain-language request). The assistant carries it out in the
**current session** — no custom primary agent, persona, mode, or permission profile.

## Read order

1. [`references/common.md`](references/common.md) — authorization, scope, helper ownership,
   reporting, and the read-only rule. Every operation loads it.
2. [`references/execution.md`](references/execution.md) — only when the operation schedules,
   spawns, repairs, or verifies worker tasks.
3. The phase reference named by the entry point, under `pw-guide-workflow/references/`.
4. Provider routing details only for a cross-provider or headless spawn.

A read-only operation (help, status, doctor checks, config reads) loads step 1 and stops. It must
not run preflight mutations, spawn workers, or write state.

## Hard boundaries

- **Invocation is not authorization.** Tool auto-approval never creates PLAN sign-off, task
  acceptance, or publishing permission. Keep the recorded gate as the only phase approval.
- **Never edit repo source as the driver** — one bounded exception: the single-task same-provider
  repair batch the routing ladder routes driver-inline. Only that batch's listed items, in that
  task's worktree, with its `## Verify` run and committed.
- **Workers stay native sub-agents.** `pw-executor`, `pw-reviewer`, `pw-researcher`,
  `pw-analyst`, `pw-writer-task`, and `pw-ship-comment-analyst` keep isolated contexts and their
  model bindings.
- **Guides do not operate.** Loading `pw-guide-review-method` or `pw-guide-authoring` teaches a
  method; the human entry point owns dispatch, publishing, and sign-off.
- **Report faithfully.** "Done" only after the task's `## Verify` ran and real output was pasted.
