# Memory policy (optional, pluggable)

The pipeline **does not depend on any specific memory tool.** Memory is a bonus, never a gate — if
you don't use one, the workflow runs exactly the same and nothing blocks.

## The always-available record
Every project already keeps its durable decisions in two places on disk, with **no external tool
required**:
- **`<project>/README.md` → "Decisions & learnings"** — what you decided and why, what to do
  differently next time.
- **`<project>/LOG.md`** — the append-only audit trail.

If you have **no** memory tool, that's the whole story: agents record learnings there and **skip**
every "search memory" / "seed memory" step. They must never refuse or stall because a memory tool
is absent.

## If you DO use a memory tool
Configure it in your gitignored `pw.config.sh` (copied from `pw.config.example.sh`):

```sh
PW_MEMORY="none"          # "none" (default) | a short name for your tool, e.g. "everos", "mem0"
PW_MEMORY_NOTES=""        # free text: how the agent should search/seed it, buckets, scopes, etc.
```

`PW_MEMORY` is a human-facing signal (surfaced by `bootstrap.sh` / `pw-doctor.sh`); the actual
"how" for an agent usually comes from that agent's own setup — an MCP server plus the agent's
global instructions (e.g. a Claude Code / KiloCode `CLAUDE.md`/rules file that already says how to
use the tool). `PW_MEMORY_NOTES` is where you write a one-paragraph reminder for teammates or a
different agent.

### Where the `/pw-*` commands touch memory (only when configured)
- **`/pw-analyze`** — *search* memory first for prior context on the domain/repos, fold in what's
  relevant, and cite it. Skip silently if `PW_MEMORY=none`.
- **`/pw-close`** — *seed* durable, workflow-level learnings (not what the repos/commits already
  record). Skip silently if `PW_MEMORY=none`; the "Decisions & learnings" section still captures them.

### Examples
- **No tool:** `PW_MEMORY="none"` → agents only use README/LOG. (Default; what teammates get.)
- **EverOS (the maintainer's setup):** `PW_MEMORY="everos"`, and the notes point at the buckets
  (`personal` for workflow/tooling, `midtrans` for domain, `workspace-<repo>` per repo). The actual
  search/seed calls come from the agent's own EverOS rules, not from this bundle.
- **Something else (mem0, a wiki, a notes repo):** name it in `PW_MEMORY`, describe the how in
  `PW_MEMORY_NOTES`, and the agent adapts.

**Rule for agents:** treat memory as best-effort enrichment. Never block, refuse, or fail a phase
because a memory tool is missing or a search returns nothing.
