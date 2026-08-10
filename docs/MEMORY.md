# Memory (optional — not required)

← [back to README](../README.md) · related: [Workflow](./WORKFLOW.md) · [Reference](./REFERENCE.md)

## What "memory" means here, and why you'd want it

Every project already keeps a record of what happened and why — that's what `README.md`'s
"Decisions & learnings" section and `LOG.md` are for, and they need **no external tool at all**.
"Memory" here means something *in addition* to that: a place an agent can **search across
projects**, not just within the one it's working on.

The benefit is concrete: without it, every new project starts from a blank slate — the agent
re-derives context it may have already worked out three projects ago ("we tried disabling that
feature flag before and it broke staging"), or repeats a question you've already answered once.
With a memory tool wired in, `/pw-analyze` searches it before writing anything, so prior decisions,
known gotchas, and domain context actually carry forward instead of being re-discovered (or
missed) every time.

This is genuinely optional. If you don't configure one, nothing about the pipeline changes —
every phase still works exactly the same, using only the project's own `README.md` + `LOG.md`.

## Turning it on

One config block in your gitignored `pw.config.sh` (copied from `pw.config.example.sh` on first
`./bootstrap.sh`):

```sh
PW_MEMORY="none"          # "none" (default) | a short name for your tool, e.g. "everos", "mem0"
PW_MEMORY_NOTES=""        # free text: how the agent should search/seed it — buckets, scopes, etc.
```

`PW_MEMORY` is a signal, not a plug-in interface — the bundle doesn't ship code that calls into any
specific memory tool. The actual mechanics (how to search, how to seed, what a "bucket" means)
come from wherever *your* agent CLI is already told about that tool (an MCP server, a rules file,
a project's own `AGENTS.md`/`CLAUDE.md`). `PW_MEMORY_NOTES` is where you write the one paragraph a
teammate — or a different agent CLI — needs to actually use it correctly.

## Where the pipeline touches it (only when configured)

| Command | What it does with memory |
|---|---|
| `/pw-analyze` | **Searches** first for prior context on the domain/repos, folds in what's relevant, cites it. |
| `/pw-close` | **Seeds** durable, workflow-level learnings — not what the commits/repos already record. |

Both steps are skipped silently when `PW_MEMORY="none"` — an agent must never block, refuse, or
stall a phase because a memory tool is missing or a search comes back empty.

## Examples

- **No tool** (the default, what a fresh teammate gets): `PW_MEMORY="none"` → agents rely on each
  project's own `README.md`/`LOG.md` only.
- **A shared team tool** (e.g. EverOS, Mem0, a notes repo you already use): name it in
  `PW_MEMORY`, and use `PW_MEMORY_NOTES` to describe *how* — which buckets/scopes apply to this
  bundle's own workflow knowledge versus a specific project's domain knowledge, if your tool
  distinguishes those.

## Going deeper

The exact agent-facing contract (skip-silently rule, the two touch points above, spelled out for
an agent reading it mid-phase) lives in [`tooling/docs/memory.md`](../tooling/docs/memory.md) — you
shouldn't need to open it unless you're debugging why an agent isn't searching/seeding as expected.
