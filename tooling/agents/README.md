# tooling/agents/ — seedable sub-agent definitions

Provider-neutral agent definitions that `bootstrap.sh` **seeds into each enabled CLI's agent dir**,
exactly like `commands/` are seeded as slash-commands. One source here → a native agent in every
provider you use. They are **build artifacts** in the provider dirs — never hand-edit the installed
copies; edit the canonical file here and re-run [`gen-agents.sh`](../scripts/toolchain/gen-agents.sh) (or
`./bootstrap.sh`).

```
tooling/agents/
├── pw-executor.md       ← runs ONE task in ONE worktree, runs ## Verify, reports; nothing else
├── pw-researcher.md     ← context/answer lane (Mode A answer w/ evidence; Mode B ground a scope →
                            pack + seed); reads context + docs + tickets; never decides
├── pw-analyst.md        ← drafts an analysis doc from a seed (options, trade-offs, Qn); read-only
├── pw-writer-task.md    ← drafts task docs from a caller's decisions; never fills ## Result
├── pw-reviewer.md       ← optional, fresh-session review pass on ONE artifact; never edits it —
│                          see docs/REVIEW.md + the `pw-guide-review-method` skill
└── pw-ship-comment-analyst.md ← read-only /pw-ship comments prerequisite: interprets every
                                 comment across the selected MRs, groups fixes, returns a
                                 fixer DAG; never fixes, replies, pushes, or approves
```

**Where they land** (per provider, via each provider's `<name>_agentdir` hook):
- **Claude Code** → `~/.claude/agents/*.md` (frontmatter `name` + `description` + `tools`)
- **kilo** → `~/.config/kilo/agent/*.md` (frontmatter `mode` + `permission` block)
- **Cursor** → `~/.cursor/agents/*.md` (frontmatter `name` + `description` + optional `model:`;
  **no** tools/permission keys — spawn access is ambient on Cursor). Its vendor compat read of
  `~/.claude/agents` is out-of-contract bleed (AGENTS golden rule: provider independence) — the
  native dir is always seeded regardless.
- **codex** → **nowhere — no defs are seeded by design.** Codex has no user-facing agent-def
  surface (`codex agents` browses sessions, not definitions), so it has no `<name>_agentdir`/
  `render_<name>_agent` hooks and gen-agents skips it. A codex driver runs Flow B (main session
  orchestrates; the `/pw-*` command-skill bodies carry the lane personas inline; delegated work
  is headless `codex exec` over the work order). The canonical defs still serve codex as
  **readable-as-file prompt bodies** (the spawn-less fallback is its normal mode).

`gen-agents.sh` stamps `{{PW_HOME}}` / `{{PW_PROJECTS}}` / `{{PW_REPOS}}` into the bodies, then each
provider's `render_<name>_agent` hook wraps the body in that provider's frontmatter (see
`../pw-common.sh`).

## Provider-specific worker defaults

A worker default configures one generated definition for one provider, because catalogs differ:
`PW_<PROVIDER>_AGENT_MODELS_<AGENT>` (for example `PW_KILO_AGENT_MODELS_PW_RESEARCHER`). Manage it
through `/pw-config global set --key agent-model --provider <p> --agent <pw-name> --value
'<model>[key=value,…]'`. The generator renders fields the definition format supports; settings it
cannot express stay invocation-time bindings and are reported on stderr. A worker default never
overrides a project role row or a task pin.

## The three facts about Kilo registration these files keep tripping on
1. **Kilo registers on *two* surfaces at once.** `gen-agents.sh` writes `~/.config/kilo/agent/<name>.md`
   (generator-owned build output — what `mode:`/`permission:` register from), and the user *may* also
   keep a `kilo.jsonc → agent` map block mirroring it (their own config, their own paste/edit). A
   name can also exist on one surface only (a map block with no md; an md with no map block = the
   new three, until mirrored — whether that md-only path registers is checked at install time with a
   reload via `pw-doctor` + the §6.4.4 Q1 test in the sub-agent plan, never assumed).
2. **`gen-agents.sh` refreshes only generated files.** It has **no `--prune`**, and it **never
   writes `kilo.jsonc`** — a generator rewriting user config (and its `permission`/`mcp`/`enabled_*`
   policy blocks) is the bug nobody wants. Retirement = delete *every surface holding a copy*, by
   hand, per the mapping docs (`docs/EXECUTION.md` + the agent plans).
3. **`pw-doctor`'s agent check is report-and-point, never self-heal into your config.** It compares
   canonical ⇄ generated md ⇄ your map blocks (where present), flags drift, and prints the refresh
   command for the md; fixing a *map* block stays your own edit.

## Reuse before you create
The six shipped agents cover the workflow's roles (researcher, analyst, writer-task, executor,
reviewer, ship-comment-analyst — `pw-reviewer` is spawned only by `/pw-review ai …`, and
`pw-ship-comment-analyst` only as the `/pw-ship comments` prerequisite). **Execution can still
reuse an existing agent you already have** (e.g. `pw-executor`) — a task's `Execute with:` names
whatever should run it, and the discipline (worktree isolation, running `## Verify`, faithful
reporting) comes from the `pw-guide-workflow` skill + the task file, not from a bespoke agent. Ship
`pw-executor` is the *single* dedicated executor concept (ad-hoc non-pw implementation runs on the
main agent or a default-agent session named by provider+model — not a second implementer
definition). `pw-reviewer` is optional —
every review point defaults to human-only (effective outcome `advisory`; a legacy stored
`off` reads that way); a pass only starts when the project's settings schedule one for that
phase, or when you ask explicitly, and `advisory` never approves.

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

## Five worker sub-agents — no bundle primary
Everything here is a **sub-agent**, spawned *in-process* by the normal session (Claude Task
`subagent_type`; kilo `mode: subagent`). A provider can spawn only its **own** sub-agents.
The bundle installs no primary agent, persona, or mode: driver procedures live in the
`pw-orchestration` skill, which runs in the ordinary session.

When a task's `Execute with:` names an agent, resolve its provider: an explicit prefix wins
(`kilo:db-migration-runner`, `claude:db-migration-runner`, `cursor:db-migration-runner`) → else the
agent's own provider → else (a
built-in with no def here) the orchestrator's own provider. Then:
- **Same provider as the orchestrator** → spawn the sub-agent in-process (the normal path).
- **Different provider** → shell out to that CLI (`kilo run --auto -m <model> …`, `claude -p`,
  `agent -p --force --model <id>` for cursor, or `codex exec -m <slug>` for codex — prompt on
  stdin) via its `<name>_headless()` template
  passing the **task file + skill inline** to its default/primary agent. You **cannot** name the
  other provider's *sub-agent* across the boundary — e.g. a Claude orchestrator delegating to kilo
  does NOT use kilo's `pw-executor`; kilo's default agent runs the task file instead. So each
  provider's `pw-executor` only helps when *that* provider is the orchestrator.

Record the concrete `provider:model(+flags)` in the task's `Actually used:` — and, for every spawn a
`LOG.md` line records, the provider's **session id** too (`pw-research` docs in
`docs/EXECUTION.md` §Spawn ledger): a later fix/resume/re-review pass **resumes the same session**
(`kilo run --session <ses_…>` / `-c`, `--fork`; claude `--resume`/`/resume`; cursor
`agent -p --force --resume <session-id>` — plain UUID, not kilo's `ses_…`; codex
`codex exec resume <thread_id>` — plain UUID from its `thread.started` JSONL event, cd to the
worktree first: resume has no directory flag) instead of cold-spawning
when the id is live, and cold-spawns a plain-model session with the recorded seed only when it's
dead. The session id is a machine-local pointer — never pushed into MR text or committed artifacts;
the on-disk PLAN/dashboard/task state stays the durable cross-machine recovery.

The phase roles without a task file (researcher / analyst / writer-task / reviewer / verifier /
ship-comment-analyst) bind their model one rung up the ladder: an interactive override for that spawn, the project
dashboard's `- **AI Models:**` line (`pw-config.sh set --project <slug> --key ai-model --set <role>=<provider:model>`,
the sibling of `- **AI Review:**`; the human surface is `/pw-config`), or nothing — which
falls through to the provider's floor (`small_model`/`subagent_model` on kilo; the session model on
claude). Canonical defs ship with `model:` **unset** on purpose: a provider alias baked into a def
is a false pin on the other provider. The executor keeps its per-task `Execute with:`; the ladder
never overrides a task file.

## Cursor-specifics (probed 2026-09-09)
- Defs auto-register from `~/.cursor/agents/*.md`; unknown frontmatter keys are tolerated (gray-matter),
  so a bundle `model:` line rides through when a canonical ever sets one — verified accepted.
- No CLI primary-agent slot: cross-provider → cursor is always **model + task file**
  (`agent -p --force --model <id>` per `cursor_headless()`), never `--agent <name>`.
- Spawn is ambient: a sub-agent is picked by `description` match or explicit `/pw-<agent>`. A
  **direct** sub-agent may itself spawn one more level (verified 2-level) — enough for one bounded
  wave; fast-tier ids are unreliable at it, so route executors to capable models (same doctrine as
  kilo's MiniMax-vs-flash-lite line in providers.md).

## Codex-specifics (probed 2026-10-04)
- No agent defs, no in-process spawn, no Flow C — a codex driver IS the orchestrator (Flow B) and
  every delegated run is a supervised headless `codex exec` (prompt via stdin; an 18KB trailing
  arg exits 0 having written nothing — artifact checks prove runs, not exit codes).
- Its `/pw-*` commands are generated **skill dirs** (`~/.codex/skills/<name>/SKILL.md`,
  explicit-invocation-only via `agents/openai.yaml` policy) — codex removed custom prompts in
  0.117.0, so skills are its only slash surface. Skills and commands share one namespace: the
  `pw-review`/`pw-rfc` bundle skills are skipped there (the command-skills own the names) and
  their METHOD travels read-as-file in reviewer spawn prompts.
- Session/ledger: `thread_id` (UUID) from the `--json` `thread.started` event; liveness =
  `pw-session.sh session-check --provider codex --session <id>` (rollout file under `~/.codex/sessions/`); resume =
  `codex exec resume <id>` (cd first — no `-C` on resume).
- Models: bare visible slugs from `codex debug models`; effort = per-run reasoning-effort
  override; Fast = per-run `service_tier="priority"` on the SAME slug (requested-only — invalid
  values are silently ignored, so record what was requested). No `PW_CODEX_API_PROVIDERS` axis.

## What the *surfaces* actually do (probed 2026-09-04 kilo; `kilo agent list` / `kilo debug agent <name>`
are the ground truth — reload the client before trusting either)

1. **A generated `agent/<name>.md` with `mode:` + `options:` registers on its own** — no map block
   needed. A `kilo.jsonc → agent` mirror block is the user's convenience (prompt/`model:` there);
   `pw-doctor`'s drift check compares canonical ⇄ generated md ⇄ map block, report-only. `model:`
   in the **md wins** over a mirror block's `model:` on this build.
2. **`kilo run --agent <name>`** resolves *primary* defs only; a `mode: subagent` name prints a
   falling-back-to-default warning and keeps going (never assume the headless run used the def), and
   an unknown name falls back **silently**. Cross-provider work order = the task file, not a name.
3. **Claude defs carry a `model:` line when a canonical sets one; Kilo generated md do too** (as of
   the 2026-09 regen) — but **canonical bundle defs ship `model:` unset** (ladder §AI Models above):
   a provider id baked into a shared def is a false promise on the other provider. Per-agent model
   pinning on kilo is still possible *for the user* via their own map-block mirror; the bundle never
   writes one (generator-never-touches-config rule; see docs/EXECUTION.md's provider-capability
   note).
