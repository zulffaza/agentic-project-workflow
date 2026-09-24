# tooling/ — command source of truth + generator

**Maintainer entry points:** [`AGENTS.md`](./AGENTS.md) (agent-facing: doctrine + implementation map + change/test protocol —
imported by `CLAUDE.md`), [`docs/testing.md`](./docs/testing.md) (the test flow), this README (human how-to).


The `/pw-*` slash commands are duplicated across agent tools (Claude Code, kilo, …), but you
**maintain them in one place** here. The per-provider files are generated build artifacts.

```
tooling/
├── scripts/                  ← every executable script (L-rules: tooling/docs/conventions.md)
│   ├── entities/             the 10 entity entry points — what commands/agents/skills invoke
│   │   ├── pw-status.sh        project state: status report + dashboard/LOG setters
│   │   │                       (log · status · oneliner · adopted · phase · dashboard-task-status · task-accept)
│   │   ├── pw-preflight.sh     gate validation before expensive agent invocations
│   │   ├── pw-review.sh        review-doc: init/init-all · signoff · add-item · answer ·
│   │   │                       add-question · resolve · gate · has-open · count · scan ·
│   │   │                       reindex · archive · reopen · note-init · auto-signoff
│   │   ├── pw-context.sh       context-doc: req-init · add-input · add-repo · fetch ·
│   │   │                       adopt-snapshot · adopt
│   │   ├── pw-ship.sh          ship/MR: resolve · exec · monitor · mr-state · mr-state-batch ·
│   │   │                       comment-seen · dashboard-mr-state
│   │   ├── pw-rfc.sh           rfc-doc: init · target · state · comment-seen · dashboard · comments
│   │   ├── pw-worktree.sh      worktree: create · remove · teardown
│   │   ├── pw-doc.sh           docs: lint · summary · sync
│   │   ├── pw-config.sh        config: project show|get|set|ensure · global show ·
│   │   │                       model-check · model-resolve (+ deprecated ai-model/ai-review shims)
│   │   └── pw-help.sh          discovery: overview · command · operators · project ·
│   │                           workflow · find (read-only how-to map + search; --json)
│   ├── lib/                  source-only libraries — invisible to callers (L2)
│   │   ├── pw-common.sh        roots + config + provider hooks (every entity sources it)
│   │   └── pw-mdlib.sh         pure markdown-document primitives
│   └── toolchain/            bundle-maintenance scripts — the toolchain test: operand = the
│                             bundle itself (L3); never in the automation registry
│       ├── scaffold.sh         creates a new project from ../../template/
│       ├── gen-commands.sh     stamps commands/ into each provider's format + location
│       ├── gen-agents.sh       seeds agents/ into each provider's agent dir
│       └── pw-doctor.sh        checks installed skills + commands + agents match this bundle (--fix repairs)
├── commands/           ← THE source of truth for /pw-* (provider-neutral)
│   ├── pw-new.md        frontmatter: description, args, [agent]; body uses {{ARGS}} + {{PW_*}}
│   ├── pw-analyze.md
│   ├── … (pw-adopt, pw-breakdown, pw-review, pw-execute, pw-ship, pw-sync, pw-status, pw-doctor)
│   └── pw-close.md
├── agents/             ← THE source of truth for seedable sub-agents: pw-orchestrator, pw-executor,
│                         pw-reviewer (optional, only spawned by /pw-review … ai), pw-researcher,
│                         pw-analyst, pw-writer-task (the phase lanes — see agents/README.md)
├── docs/               ← registries/policy the AGENTS read (each has a human-facing peer doc);
│                         maintainer-owned reference — you never edit these, see below:
│   ├── conventions.md    capability placement: S-rules (script), L-rules (layout),
│   │                     C-rules (commands), A-rules (arguments), D-rules (doc layers +
│   │                     issue routing) — read before adding anything
│   ├── known-issues.md   maintainer backlog: UNFIXED defects (dated, evidence-linked);
│   │                     settled records live with their mechanism doc, user symptoms in
│   │                     ../../docs/TROUBLESHOOTING.md (D-rules)
│   ├── scripts/          usage reference for the entity scripts (how to call, how to
│   │   └── README.md       read the output, what to do on failure — no internals)
│   ├── testing.md        the change-test harness (tiers, fixtures, mutation register)
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
│   ├── pw-review/SKILL.md           ← standalone, portable review method — usable by ANY agent,
│   │                                  not only the generated pw-reviewer sub-agent
│   └── pw-rfc/SKILL.md              ← RFC-authoring guide for the /pw-rfc side-loop
├── tests/              ← the change-test harness (pw_test.sh — see docs/testing.md)
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

The entity scripts make the load-bearing, format-sensitive steps deterministic instead of
hand-edited prose — the `/pw-*` commands call `pw-status.sh status|oneliner|adopted|log|phase`,
`pw-review.sh init|gate|reindex|…`, `pw-context.sh adopt|…` rather than asking the agent to edit
the dashboard (or copy a review template) by hand. `status` refuses accidental backward phase
moves (`--rewind` to intend one); creation operators are idempotent, so re-running a command never
clobbers work in progress. Each entity script carries its own `--selftest` (the harness runs them;
see `docs/testing.md`).

The **10 entity scripts** in `scripts/entities/` push that idea further:
whole deterministic steps — gates, doc validation, status reports, ship mechanics, URL
fetching — run as zero-token scripts instead of agent reasoning. **Commands call them as
pre-flight; agents and skills call the same ones** so behavior is identical whichever path
triggers the work (see each agent/skill's script notes, and `docs/scripts/README.md` for
the reference).

**Information boundary in `docs/`:** two kinds live there. *Behavioral* docs answer "how does
this part of the workflow work" and a curious user may read them (`forges.md`, `memory.md`,
`rfc.md`, plus everything under `scripts/`). *Technical* docs are maintainer implementation
reference — registries and invocation mechanics an agent reads at runtime (`providers.md`,
`rfc-backends.md`). Each file carries an `Audience:` note saying which; neither kind leaks into
the bundle's user-facing `../docs/` — users drive everything through `/pw-*` commands and never
need to know a script ran.

`providers.md` documents the cross-provider execution mechanism — how the orchestrator invokes a
*different* Agent Provider's CLI headlessly, reading that provider's `<name>_headless()` hook
(built-in for claude/kilo/opencode/cursor in `pw-common.sh`, added or overridden in
`pw.config.sh` —
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
$PW_HOME/tooling/scripts/toolchain/gen-commands.sh
```
Outputs (overwritten each run):
- **Claude Code** → `~/.claude/commands/*.md` (frontmatter `description` + `argument-hint`)
- **kilo CLI** → `~/.config/kilo/command/*.md` (frontmatter `description` + `agent:` when set)

`{{ARGS}}` is replaced with each provider's argument placeholder (both use `$ARGUMENTS` today).

## Add / enable an Agent Provider
Already `claude`, `kilo`, `opencode`, or `cursor`? Those are **built in** — just add the name to
`PW_PROVIDERS=(…)` in `../pw.config.sh`, nothing else. For any other CLI, **you never edit these
scripts** — everything else also goes in `../pw.config.sh`:
1. Add its name to `PW_PROVIDERS=(…)`.
2. Define `<name>_bin` / `<name>_skilldir` / `<name>_commanddir` / `render_<name>_command` (the
   scripts only supply defaults for the built-ins, so yours win — never redefine a built-in
   provider's hooks here, it'll silently replace the working default). Copy
   `render_claude_command`/`render_kilo_command`/`render_cursor_command` from `pw-common.sh` as
   a starting point; full
   variable contract in [ONBOARDING.md](../ONBOARDING.md#register-a-new-provider). *(Optional)*
   to also seed the sub-agents for it, define `<name>_agentdir` + `render_<name>_agent`;
   providers without those just skip agent-seeding.
3. *(Optional)* define `<name>_headless()` — its exact non-interactive invocation template, so an
   orchestrator on a *different* provider can shell out to this one (cross-provider execution).
   Not needed for the CLI to work at all, same-provider-only. See `docs/providers.md`.
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
> agent dir by `gen-agents.sh` (kilo `~/.config/kilo/agent/`, Claude Code `~/.claude/agents/`,
> Cursor `~/.cursor/agents/`). The
> six shipped roles: `pw-orchestrator`, `pw-executor`, `pw-reviewer` (optional — off by default
> per phase) and the spawn-lanes `pw-researcher` / `pw-analyst` / `pw-writer-task`; execution can
> still reuse a registered agent (e.g. `pw-executor`) by naming it in a task's `Execute with:` —
> or, the portable Option-A form, route a `provider:model` and let the task file be the work order
> (Option A: one executor concept, no second implementer def). Lane spawns take their model from the
> project's `- **AI Models:**` row (`pw-config.sh ai-model`); spawns are ledgered with their session id
> so later repairs resume the same session (`docs/EXECUTION.md` §Spawning phase work + §The
> per-spawn ledger).


## changing tooling — the test protocol (`tooling/tests/`)

Anything under `tooling/` or `template/` changes the contract the **entity scripts**
keep. The full agent-change protocol — tiers, which tier for which change type, the corpus
gate — is [`docs/testing.md`](./docs/testing.md). One command summary:
**`tooling/tests/pw-test.sh all` before every commit; `--mutation <new-fix>` after any fix**
(its `expectations/mutations.tsv` reverts each documented fix and proves a test sees it).
