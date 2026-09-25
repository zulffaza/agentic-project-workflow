# TOOLING.md — the machinery, pinned

← [back to README](../README.md) · related: [Reference](./REFERENCE.md) · [Execution](./EXECUTION.md)

This is the **one place** in the user docs that tells you where the machinery lives and what's
where. You never need it to run projects — the `/pw-*` commands and the `project-workflow` skill
are the interface. Read it if you're technical/curious about how the commands work underneath, or
if you're about to become a maintainer (then stop here and open
[`tooling/AGENTS.md`](../tooling/AGENTS.md) — the real entry point for that job).

## What the machinery is

`tooling/` (next to this `docs/` dir, in the bundle repo) holds everything the `/pw-*` commands
call underneath:

| Path | What lives there |
|---|---|
| `tooling/scripts/` | the executables — `entities/` (one script per project artifact: status, review, context, config…), `lib/` (shared plumbing), `toolchain/` (scaffold, generators, doctor) |
| `tooling/commands/` | the canonical `/pw-*` prompt sources (provider-neutral; the installer/generators stamp a copy into each CLI's command dir — **never hand-edit those copies**; `/pw-doctor --fix` regenerates them from here) |
| `tooling/agents/` | the canonical sub-agent defs (`pw-orchestrator`, `pw-executor`, `pw-reviewer`, `pw-researcher`, `pw-analyst`, `pw-writer-task`), seeded into each CLI's agent dir |
| `tooling/skill/` | the shipped skills (`project-workflow`, `pw-review`, `pw-rfc`), installed by `bootstrap.sh` |
| `tooling/docs/` | the maintainer/agent reference docs — the deep "how and why" behind the mechanisms the `docs/` guides describe behaviorally |
| `tooling/tests/` | the regression harness (canaries, per-script selftests, fixture battery, mutation register) that guards every change to the above |

## Where a deep answer lives

The `docs/` guide says *what to do*; the paired maintainer doc says *how it works*. Pointers by
topic:

| You're curious about… | Look in |
|---|---|
| which CLI runs which model; Effort/Thinking flag mapping; headless invocation mechanics; **the hook contract for registering a new Agent Provider** (+ the worked Cline example) | [`tooling/docs/providers.md`](../tooling/docs/providers.md) |
| how review-file items, signoff rows, and context-request edits are made deterministic | [`tooling/docs/scripts/review-and-context-editing.md`](../tooling/docs/scripts/review-and-context-editing.md) |
| the forge-side mechanics of MR comments (standalone vs diff-anchored, what can never "resolve") | [`tooling/docs/forges.md`](../tooling/docs/forges.md) |
| the memory search/seed touch points, spelled out for agents | [`tooling/docs/memory.md`](../tooling/docs/memory.md) |
| RFC publishing internals and backend contracts (the 4-operation interface; which backends are implemented) | [`tooling/docs/rfc.md`](../tooling/docs/rfc.md) + [`tooling/docs/rfc-backends.md`](../tooling/docs/rfc-backends.md) |
| a script's exact operators, exit codes, and fix hints | [`tooling/docs/scripts/README.md`](../tooling/docs/scripts/README.md) — usage reference (you drive the flows via `/pw-*` commands, not the scripts) |
| the worktree teardown helper when working from the bundle | [`tooling/docs/scripts/`](../tooling/docs/scripts/) usage reference |
| bundle layout detail (the `tooling/` sub-tree this page summarizes) | [`tooling/AGENTS.md`](../tooling/AGENTS.md) §implementation map |

## Three facts worth knowing before you poke around

- **Sources-only.** Everything under `tooling/` is the single source of truth; the copies in
  `~/.claude/`, `~/.cursor/`, `~/.config/kilo/`, … are generated. A fix made only in a generated
  copy is destroyed by the next `/pw-doctor --fix` — move it into the source and regenerate.
- **The harness guards the boundary.** Doctrine like this page's existence is mechanically tested:
  user docs stay behavioral, maintainer docs stay mechanism-side, and published files carry no
  internal planning references. `tooling/tests/` runs the checks.
- **`tooling/docs/providers.md` is machine/account-specific reference**, not code — model IDs and
  available providers differ per person; treat the committed version as a starting point.
