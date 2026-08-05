# sub-agent/ — custom agent definitions (rarely needed)

**Reuse before you create.** The executor role is fulfilled by an **existing agent** (e.g.
`code-implementation`) plus the `project-workflow` skill — not a bespoke agent. A task's
`Execute with:` field names an existing agent or a model, and the orchestrator spawns that. So
you usually need **nothing** here.

Add a definition here only for a **genuinely new role** that no existing agent covers, and that
recurs across tasks — e.g. a "db-migration-runner" that always runs a specific migration+verify
sequence. Use [`_TEMPLATE.md`](./_TEMPLATE.md).

Two roles the workflow assumes:
- **orchestrator** — reads `task/PLAN.md`, owns the DAG, spawns executors, never edits repo code.
  (In kilo this is the `pw-orchestrator` agent; in Claude Code it's the `/pw-execute` prompt.)
- **executor** — runs one task in one worktree. **Reuse an existing agent for this**; the skill +
  task file supply the discipline. Don't mint a parallel executor.

If a def here should also exist as a provider-native agent (e.g. a kilo agent under
`~/.config/kilo/agent/`), keep this dir the human-readable source of truth and mirror it there.

## Agents are provider-bound too
Just like a model, **an agent runs under a provider** — see [`_TEMPLATE.md`](./_TEMPLATE.md)'s
`Provider:` / `Default model:` fields and the [provider registry]({{PW_HOME}}/tooling/providers.md). When
a task's `Execute with:` names an agent, the orchestrator resolves its provider as:
1. an explicit prefix on `Execute with:` wins — `kilo:db-migration-runner`, `claude:code-implementation`;
2. else the `Provider:` declared in this agent's `sub-agent/<name>.md`;
3. else (a built-in agent with no def here, e.g. `code-implementation`) default to the
   **orchestrator's own provider**.

Then it spawns per that provider: **same provider as the orchestrator** → in-process (Claude Code
Task `subagent_type`, or a kilo native agent when kilo is orchestrating); **different provider** →
shell out to that CLI with its native-agent flag when one exists (`kilo run --agent <name> -m
<model> …`), otherwise pass the agent's brief + task file inline as the prompt. The agent's
`Default model` / `Default effort` apply unless the task overrides them. Record the concrete
provider:model(+flags) in the task's `Actually used:`.
