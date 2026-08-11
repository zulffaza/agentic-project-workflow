# tooling/ — command source of truth + generator

The `/pw-*` slash commands are duplicated across agent tools (Claude Code, kilo, …), but you
**maintain them in one place** here. The per-provider files are generated build artifacts.

```
tooling/
├── scaffold.sh         ← creates a new project from ../template/
├── gen-commands.sh     ← stamps commands/ into each provider's format + location
├── gen-agents.sh       ← seeds agents/ into each provider's agent dir (same idea as gen-commands)
├── pw-common.sh        ← shared plumbing (roots + config + provider hooks) for the scripts below
├── pw-lib.sh           ← mechanical helpers the commands call: status / oneliner / adopted / adopt /
│                         review-init / log / phase / ai-review / review note-init|auto-signoff
├── pw-doctor.sh        ← checks installed skills + commands + agents match this bundle (--fix repairs)
├── pw-teardown.sh      ← safe worktree removal at close-out (won't nuke your CWD / dirty trees)
├── commands/           ← THE source of truth for /pw-* (provider-neutral)
│   ├── pw-new.md        frontmatter: description, args, [agent]; body uses {{ARGS}} + {{PW_*}}
│   ├── pw-analyze.md
│   ├── … (pw-adopt, pw-breakdown, pw-review, pw-execute, pw-ship, pw-sync, pw-status, pw-doctor)
│   └── pw-close.md
├── agents/             ← THE source of truth for seedable sub-agents (pw-orchestrator, pw-executor,
│                         pw-reviewer — the last optional, only spawned by /pw-review … ai)
├── docs/               ← registries/policy the AGENTS read (each has a human-facing peer doc);
│                         maintainer-owned reference — you never edit these, see below:
│   ├── providers.md      cross-provider execution mechanism (headless invocation hooks)
│   │                     — human peer: ../../docs/EXECUTION.md
│   ├── memory.md         optional/pluggable memory policy (the pipeline works with none)
│   │                     — human peer: ../../docs/MEMORY.md
│   ├── forges.md         git-forge registry (repo host → gh/glab CLI + invocation)
│   │                     — human peer: ../../docs/REVIEW.md
│   ├── rfc.md            optional/pluggable RFC-publishing policy (works with none)
│   └── rfc-backends.md   RFC backend registry (doc platform → create/fetch/update/comments)
│                         — human peer for both: ../../docs/RFC.md
├── skill/              ← every subdir with a SKILL.md here is a shippable skill (bootstrap installs
│   ├── project-workflow/SKILL.md      each one, per provider):
│   └── pw-review/SKILL.md           ← standalone, portable review method — usable by ANY agent,
│                                       not only the generated pw-reviewer sub-agent
└── README.md
```

**This dir is the machinery, not the intended reading path — and it's never edited by a user,
only by whoever maintains this bundle.** A human using the pipeline should be able to do
everything from the bundle's own `docs/` + the `/pw-*` commands; the files above are what an
agent reads to actually run a phase. Any per-user customization goes in `pw.config.sh` instead —
registering a new Agent Provider, its optional cross-provider `_headless()` hook, a forge-host
override (`PW_FORGE_HOSTS`), or an RFC backend setting (`PW_RFC_*`) are all hooks/variables there,
never a hand-edit to a file in this directory. If you're just using the pipeline, you shouldn't
need to open this directory at all.

`pw-lib.sh` makes the load-bearing, format-sensitive steps deterministic instead of hand-edited
prose — the `/pw-*` commands call `pw-lib.sh status|oneliner|adopted|adopt|review-init|log|phase`
rather than asking the agent to edit the dashboard (or copy a review template) by hand. `status`
refuses accidental backward phase moves (`--rewind` to intend one); `review-init` is idempotent, so
calling it on every `/pw-analyze`/`/pw-breakdown` run never clobbers a review already in progress.
Run `pw-lib.sh selftest` after changing it.

`providers.md` documents the cross-provider execution mechanism — how the orchestrator invokes a
*different* Agent Provider's CLI headlessly, reading that provider's `<name>_headless()` hook
(built-in for claude/kilo/opencode in `pw-common.sh`, added or overridden in `pw.config.sh` —
never edited here). `forges.md` and `rfc-backends.md` are maintainer-owned the same way — the
day-to-day settings you actually set (`PW_FORGE_HOSTS`, `PW_RFC_BACKEND`/`PW_RFC_LARK_*`) already
live in `pw.config.sh`; `forges.md` documents how a repo's git host resolves to the `gh`/`glab`
CLI so nothing hardcodes an org's hostname, `rfc-backends.md` documents each RFC doc platform's
(Lark implemented; Confluence/Google Docs/Notion as contract stubs) create/fetch/update/
list-comments operations. `rfc.md` is the pluggable-policy shape instead — like `memory.md`, the
pipeline works with **no** backend configured (`/pw-rfc` still generates a local `rfc/RFC.md`;
publishing to a real platform is the opt-in part).

## Regenerate after any change
Edit a file in `commands/`, then (`$PW_HOME` = the bundle dir; `bootstrap.sh` exports it):
```bash
$PW_HOME/tooling/gen-commands.sh
```
Outputs (overwritten each run):
- **Claude Code** → `~/.claude/commands/*.md` (frontmatter `description` + `argument-hint`)
- **kilo CLI** → `~/.config/kilo/command/*.md` (frontmatter `description` + `agent:` when set)

`{{ARGS}}` is replaced with each provider's argument placeholder (both use `$ARGUMENTS` today).

## Add / enable an Agent Provider
Already `claude`, `kilo`, or `opencode`? Those are **built in** — just add the name to
`PW_PROVIDERS=(…)` in `../pw.config.sh`, nothing else. For any other CLI, **you never edit these
scripts** — everything else also goes in `../pw.config.sh`:
1. Add its name to `PW_PROVIDERS=(…)`.
2. Define `<name>_bin` / `<name>_skilldir` / `<name>_commanddir` / `render_<name>_command` (the
   scripts only supply defaults for the built-ins, so yours win — never redefine a built-in
   provider's hooks here, it'll silently replace the working default). Copy
   `render_claude_command`/`render_kilo_command` from `pw-common.sh` as a starting point; full
   variable contract in [ONBOARDING.md](../ONBOARDING.md#register-a-new-provider). *(Optional)*
   to also seed the sub-agents for it, define `<name>_agentdir` + `render_<name>_agent`;
   providers without those just skip agent-seeding.
3. Add a row to `docs/providers.md` (its headless invocation) — a separate, optional registry
   only needed for cross-provider task routing, not for the CLI to work at all.
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
> three shipped roles are `pw-orchestrator`, `pw-executor`, and `pw-reviewer` (optional — off by
> default per project/phase); execution can still reuse an existing agent you have (e.g.
> `code-implementation`) by naming it in a task's `Execute with:`.
