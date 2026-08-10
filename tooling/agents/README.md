# tooling/agents/ — seedable sub-agent definitions

Provider-neutral agent definitions that `bootstrap.sh` **seeds into each enabled CLI's agent dir**,
exactly like `commands/` are seeded as slash-commands. One source here → a native agent in every
provider you use. They are **build artifacts** in the provider dirs — never hand-edit the installed
copies; edit the canonical file here and re-run [`gen-agents.sh`](../gen-agents.sh) (or
`./bootstrap.sh`).

```
tooling/agents/
├── pw-orchestrator.md   ← reads task/PLAN.md, owns the DAG, spawns executors; never edits repo code
├── pw-executor.md       ← runs ONE task in ONE worktree, runs ## Verify, reports; nothing else
└── pw-reviewer.md       ← optional, fresh-session review pass on ONE artifact; never edits it —
                            see docs/REVIEW.md + the `pw-review` skill
```

**Where they land** (per provider, via each provider's `<name>_agentdir` hook):
- **Claude Code** → `~/.claude/agents/*.md` (frontmatter `name` + `description` + `tools`)
- **kilo** → `~/.config/kilo/agent/*.md` (frontmatter `mode` + `permission` block)

`gen-agents.sh` stamps `{{PW_HOME}}` / `{{PW_PROJECTS}}` / `{{PW_REPOS}}` into the bodies, then each
provider's `render_<name>_agent` hook wraps the body in that provider's frontmatter (see
`../pw-common.sh`).

## Reuse before you create
The three shipped agents cover the three roles the workflow needs. **Execution can still reuse an
existing agent you already have** (e.g. `code-implementation`) — a task's `Execute with:` names
whatever should run it, and the discipline (worktree isolation, running `## Verify`, faithful
reporting) comes from the `project-workflow` skill + the task file, not from a bespoke agent. Ship
`pw-executor` is there for teammates who *don't* have a code agent. `pw-reviewer` is optional —
every review point defaults to human-only (AI Review mode `off`); it only ever runs when a
project's dashboard turns it on for a specific phase.

## Adding a custom agent
Only for a **genuinely new role** no existing agent covers, that recurs across tasks (e.g. a
`db-migration-runner`). Drop a `<name>.md` here with the same frontmatter shape (`description`,
`displayName`, `role`, optional `claude_tools` / `model`), then `./bootstrap.sh` to seed it. Because
`gen-agents.sh` only writes the files it finds here, it never clobbers unrelated agents in your
provider dirs.

## Canonical file format
```markdown
---
description: <one line — becomes the agent description>
displayName: <human-readable name, e.g. "PW Orchestrator">
role: orchestrator | executor | <other>   ← kilo uses this to pick mode + permissions
claude_tools: <optional CSV of Claude Code tool names, e.g. "Read, Bash, Task">
model: <optional default model>
---
<the agent's system prompt / brief, using {{PW_*}} path tokens>
```

## Agents are provider-bound — and sub-agents don't cross providers
Two kinds of thing live here, and the difference is load-bearing:
- **`pw-executor` and `pw-reviewer` are sub-agents** — spawned *in-process* (Claude Task
  `subagent_type`; kilo `mode: subagent`). A provider can spawn only its **own** sub-agents.
  `pw-reviewer` is spawned by whichever agent is running `/pw-review <slug> ai …`, not only by
  `pw-orchestrator` — any primary agent on that provider can spawn it.
- **`pw-orchestrator` is a primary/invocable agent** — run through a provider's CLI, the only unit
  that crosses a provider boundary.

When a task's `Execute with:` names an agent, resolve its provider: an explicit prefix wins
(`kilo:db-migration-runner`, `claude:code-implementation`) → else the agent's own provider → else (a
built-in with no def here) the orchestrator's own provider. Then:
- **Same provider as the orchestrator** → spawn the sub-agent in-process (the normal path).
- **Different provider** → shell out to that CLI (`kilo run --auto -m <model> …`, or `claude`)
  passing the **task file + skill inline** to its default/primary agent. You **cannot** name the
  other provider's *sub-agent* across the boundary — e.g. a Claude orchestrator delegating to kilo
  does NOT use kilo's `pw-executor`; kilo's default agent runs the task file instead. So each
  provider's `pw-executor` only helps when *that* provider is the orchestrator.

Record the concrete `provider:model(+flags)` in the task's `Actually used:`.
