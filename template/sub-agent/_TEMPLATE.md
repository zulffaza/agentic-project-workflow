# Sub-agent: <name>

- **Role:** orchestrator | executor | reviewer | <other>
- **Provider:** claude | kilo | <other from `{{PW_HOME}}/tooling/providers.md`> — the CLI that runs this
  agent. Determines HOW the orchestrator spawns it (in-process if it matches the orchestrator's own
  provider, else shelled out to this provider's CLI).
- **Default model:** <provider-qualified model this agent runs with> — e.g. `claude:claude-opus-4-8`
  or `command_code/MiniMaxAI/MiniMax-M3`. A task's `Execute with:` / `Effort:` may override.
- **Default effort / thinking:** <optional — e.g. `effort=high`, `thinking=on`>
- **Provider-native agent:** <if mirrored as a real provider agent — e.g. a kilo agent at
  `~/.config/kilo/agent/<name>.md` invoked via `kilo run --agent <name>`, or a Claude Code Task
  `subagent_type` — name it here; else "none — the skill + task file supply the discipline">
- **When to use:** <the trigger — what kind of task this is spawned for>

## Brief
What this agent is responsible for, in 2–3 sentences.

## Must
- <hard rules, e.g. "work only inside the assigned worktree">
- Run the task's `## Verify` block and paste real output before reporting done.
- Report faithfully — state failures and skips.

## Must not
- <e.g. "touch files outside the worktree", "open PRs without the exit strategy in PLAN.md">

## Inputs it reads
- <task file, specific analysis sections, specific context>

## Output / handoff
- <what it produces and how it reports back to the orchestrator>
