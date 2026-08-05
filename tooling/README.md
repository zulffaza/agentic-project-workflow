# tooling/ — command source of truth + generator

The `/pw-*` slash commands are duplicated across agent tools (Claude Code, kilo, …), but you
**maintain them in one place** here. The per-provider files are generated build artifacts.

```
tooling/
├── scaffold.sh         ← creates a new project from ../template/
├── gen-commands.sh     ← stamps commands/ into each provider's format + location
├── pw-common.sh        ← shared plumbing (roots + config + provider hooks) for the scripts below
├── pw-lib.sh           ← mechanical helpers the commands call: status / oneliner / log / phase
├── pw-doctor.sh        ← checks installed skill + commands match this bundle (--fix repairs)
├── pw-teardown.sh      ← safe worktree removal at close-out (won't nuke your CWD / dirty trees)
├── commands/           ← THE source of truth for /pw-* (provider-neutral)
│   ├── pw-new.md        frontmatter: description, args, [agent]; body uses {{ARGS}} + {{PW_*}}
│   ├── pw-analyze.md
│   ├── … (pw-breakdown, pw-review, pw-execute, pw-ship, pw-status, pw-doctor)
│   └── pw-close.md
├── providers.md        ← agent provider registry (model → CLI, headless invocation) [🧑 you]
├── memory.md           ← optional/pluggable memory policy (the pipeline works with none)
├── skill/project-workflow/SKILL.md   ← the shippable skill (bootstrap installs it per provider)
└── README.md
```

`pw-lib.sh` makes the load-bearing, format-sensitive steps deterministic instead of hand-edited
prose — the `/pw-*` commands call `pw-lib.sh status|oneliner|log|phase` rather than asking the agent
to edit the dashboard by hand. `status` refuses accidental backward phase moves (`--rewind` to
intend one). Run `pw-lib.sh selftest` after changing it.

`providers.md` is **not** generated — it's a config file you maintain (which CLI runs which
model, and how to invoke it headlessly for cross-provider execution). See it to add a new
model/provider.

## Regenerate after any change
Edit a file in `commands/`, then (`$PW_HOME` = the bundle dir; `bootstrap.sh` exports it):
```bash
$PW_HOME/tooling/gen-commands.sh
```
Outputs (overwritten each run):
- **Claude Code** → `~/.claude/commands/*.md` (frontmatter `description` + `argument-hint`)
- **kilo CLI** → `~/.config/kilo/command/*.md` (frontmatter `description` + `agent:` when set)

`{{ARGS}}` is replaced with each provider's argument placeholder (both use `$ARGUMENTS` today).

## Add / enable a provider
**You never edit these scripts** — everything is in `../pw.config.sh`:
1. Add its name to `PW_PROVIDERS=(…)`.
2. Define `<name>_bin` / `<name>_skilldir` / `<name>_outdir` / `render_<name>` (the scripts only
   supply defaults for the built-ins, so yours win). Copy `render_claude`/`render_kilo` from
   `gen-commands.sh` as a starting point.
3. Add a row to `providers.md` (its headless invocation).
4. Re-run `./bootstrap.sh` (or `gen-commands.sh`).

That's the whole cost of onboarding a provider — the phase prompts themselves never get copied.

## Canonical file format
```markdown
---
description: <one line, becomes the command description>
args: <argument hint, e.g. "<project-slug> [focus]">
agent: <optional — a provider agent to run the command under, e.g. pw-orchestrator>
---
<prompt body, using {{ARGS}} where the invocation's arguments go>
```

> Agents (kilo `~/.config/kilo/agent/`, Claude Code's Task tool) are **not** generated from here —
> they're few and provider-shaped. Only the `pw-orchestrator` coordinator is custom; executors
> reuse existing agents (see `../template/sub-agent/README.md`).
