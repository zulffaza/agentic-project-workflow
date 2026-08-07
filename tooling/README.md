# tooling/ — command source of truth + generator

The `/pw-*` slash commands are duplicated across agent tools (Claude Code, kilo, …), but you
**maintain them in one place** here. The per-provider files are generated build artifacts.

```
tooling/
├── scaffold.sh         ← creates a new project from ../template/
├── gen-commands.sh     ← stamps commands/ into each provider's format + location
├── gen-agents.sh       ← seeds agents/ into each provider's agent dir (same idea as gen-commands)
├── pw-common.sh        ← shared plumbing (roots + config + provider hooks) for the scripts below
├── pw-lib.sh           ← mechanical helpers the commands call: status / oneliner / adopted / adopt / review-init / log / phase
├── pw-doctor.sh        ← checks installed skill + commands + agents match this bundle (--fix repairs)
├── pw-teardown.sh      ← safe worktree removal at close-out (won't nuke your CWD / dirty trees)
├── commands/           ← THE source of truth for /pw-* (provider-neutral)
│   ├── pw-new.md        frontmatter: description, args, [agent]; body uses {{ARGS}} + {{PW_*}}
│   ├── pw-analyze.md
│   ├── … (pw-adopt, pw-breakdown, pw-review, pw-execute, pw-ship, pw-sync, pw-status, pw-doctor)
│   └── pw-close.md
├── agents/             ← THE source of truth for seedable sub-agents (pw-orchestrator, pw-executor)
├── providers.md        ← agent provider registry (model → CLI, headless invocation) [🧑 you]
├── memory.md           ← optional/pluggable memory policy (the pipeline works with none)
├── forges.md           ← git-forge registry (repo host → gh/glab CLI + invocation) [🧑 you]
├── rfc.md              ← optional/pluggable RFC-publishing policy (the pipeline works with none)
├── rfc-backends.md     ← RFC backend registry (doc platform → create/fetch/update/comments) [🧑 you]
├── skill/project-workflow/SKILL.md   ← the shippable skill (bootstrap installs it per provider)
└── README.md
```

`pw-lib.sh` makes the load-bearing, format-sensitive steps deterministic instead of hand-edited
prose — the `/pw-*` commands call `pw-lib.sh status|oneliner|adopted|adopt|review-init|log|phase`
rather than asking the agent to edit the dashboard (or copy a review template) by hand. `status`
refuses accidental backward phase moves (`--rewind` to intend one); `review-init` is idempotent, so
calling it on every `/pw-analyze`/`/pw-breakdown` run never clobbers a review already in progress.
Run `pw-lib.sh selftest` after changing it.

`providers.md` is **not** generated — it's a config file you maintain (which CLI runs which
model, and how to invoke it headlessly for cross-provider execution). See it to add a new
model/provider. `forges.md` and `rfc-backends.md` are the same shape (a registry you maintain,
read at ship/rfc time, no code change to add a row) — `forges.md` maps a repo's git host to the
`gh`/`glab` CLI so nothing hardcodes an org's hostname; `rfc-backends.md` maps an RFC doc platform
(Lark today; Confluence/Google Docs/Notion documented as contract stubs) to its create/fetch/
update/list-comments operations. `rfc.md` is the pluggable-policy shape instead — like
`memory.md`, the pipeline works with **no** backend configured (`/pw-rfc` still generates a local
`rfc/RFC.md`; publishing to a real platform is the opt-in part).

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
   `pw-common.sh` as a starting point. *(Optional)* to also seed the sub-agents for it, define
   `<name>_agentdir` + `render_<name>_agent`; providers without those just skip agent-seeding.
3. Add a row to `providers.md` (its headless invocation).
4. Re-run `./bootstrap.sh` (or `gen-commands.sh` + `gen-agents.sh`).

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

> Sub-agents **are** generated — from [`agents/`](./agents/README.md), seeded into each provider's
> agent dir by `gen-agents.sh` (kilo `~/.config/kilo/agent/`, Claude Code `~/.claude/agents/`). The
> two shipped roles are `pw-orchestrator` and `pw-executor`; execution can still reuse an existing
> agent you have (e.g. `code-implementation`) by naming it in a task's `Execute with:`.
