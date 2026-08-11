# Onboarding — the agentic project-workflow pipeline

This bundle is a **phased, multi-repo AI-agent workflow**: gather context → analyze → break into
tasks → execute in isolated git worktrees → review → learn. You drive it with `/pw-*` slash
commands from your agent CLI. It's provider-agnostic — it works with whatever AI coding CLI you
have (Claude Code, KiloCode, …), and you only get wired up for the ones you actually have.

Same steps whether you're a **new teammate** or **recovering a wiped machine**.

Want to see this in action first, with no setup at all? → [docs/WALKTHROUGH.md](./docs/WALKTHROUGH.md).

## Prerequisites

- `git`, `bash`, `perl` (all standard on macOS/Linux).
- A Git-forge CLI for the repos you'll ship to — `gh` (GitHub) or `glab` (GitLab). `/pw-ship`/
  `/pw-adopt` need one per repo; see [`tooling/docs/forges.md`](./tooling/docs/forges.md).
- At least one supported Agent Provider (AI-agent CLI) on your `PATH` — built in, no extra config:
  - **Claude Code** — `claude`
  - **KiloCode** — `kilo`  (KiloCode connects to many model API Providers; you pick which one(s)
    in `pw.config.sh` — the shipped default is `kilo` itself, KiloCode's own built-in gateway,
    which needs no separate credential; `command_code`/`openrouter`/etc. shown elsewhere as
    examples are just the maintainer's own additional setup, not a requirement)
  - **OpenCode** — `opencode`
  - Something else? You can add it — see [Register a new provider](#register-a-new-provider).

## Onboard in 3 steps

```bash
# 1. Clone the bundle so it sits ALONGSIDE the git repos you'll be changing —
#    i.e. inside your repos root (the default $PW_REPOS is two levels up). Any folder
#    layout works; this is just one example (a JetBrains-style "IdeaProjects/projects/"
#    layout isn't required — put it wherever your own repos root actually is):
git clone <remote-url>/agentic-project-workflow <your-repos-root>/projects/agentic-project-workflow
cd <your-repos-root>/projects/agentic-project-workflow

# 2. Bootstrap: reads pw.config.sh (created from the example on first run), installs the
#    skill + /pw-* commands for each enabled CLI, writes pw-env.sh. Idempotent and
#    non-destructive (won't clobber existing installs). Edit pw.config.sh to change providers.
./bootstrap.sh

# 3. Load the path vars into your shell (optional: add to ~/.zshrc to persist).
source ./pw-env.sh
```

**If your git repos live somewhere other than two levels above the bundle**, tell bootstrap once:

```bash
PW_REPOS=/path/to/your/repos ./bootstrap.sh
```

### Verify

```bash
/pw-new demo                    # in your agent CLI — scaffold a throwaway project
/pw-status demo                 # your CLI should know the command and report phase=context
rm -rf $PW_PROJECTS/demo        # clean up (no /pw-* command for this — just a filesystem delete)
```

If `/pw-status` is recognized and prints a status, you're onboarded.

## What bootstrap did

- Created `pw.config.sh` from `pw.config.example.sh` (first run only) and read `PW_PROVIDERS`
  from it — the CLIs you enabled.
- Resolved three path roots from the bundle's own location:
  `$PW_HOME` (this bundle) · `$PW_PROJECTS` (`$PW_HOME/..`, where projects go) ·
  `$PW_REPOS` (`$PW_PROJECTS/..`, where your git repos live).
- Installed every shipped **skill** (`project-workflow`, and `pw-review` — the standalone
  fresh-review method behind the optional AI-assisted review feature) into each enabled+detected
  CLI's skills dir (symlinked to `tooling/skill/<name>`, so bundle updates propagate).
- Generated the **`/pw-*` commands** for each enabled+detected CLI, with the real absolute paths
  stamped in (sources use `{{PW_*}}` tokens; the generator/scaffolder stamp them — the portability
  trick).
- Seeded the **sub-agents** (`pw-orchestrator`, `pw-executor`, and `pw-reviewer` — optional, off by
  default per project/phase) into each CLI's agent dir the same way (from `tooling/agents/`).
  Execution can still reuse an existing agent you have.
- Wrote `pw-env.sh`.

Re-run `./bootstrap.sh` any time (e.g. after `git pull`). Use `--force` to re-link the skill,
`--check` to detect-and-report without changing anything.

## Troubleshooting — `pw-doctor`

If a `/pw-*` command isn't found, behaves like an older version, or you just want to confirm this
machine is actually in sync with the bundle, run:

```
/pw-doctor          # report-only — never changes anything
/pw-doctor --fix    # repair whatever it found
```

**What it checks, per enabled provider:** the CLI is actually on `PATH`; every shipped skill
(`project-workflow`, `pw-review`) is installed and matches the bundle; every generated `/pw-*`
command file matches its canonical source in `tooling/commands/`; the seeded sub-agents match
`tooling/agents/`. Reading the
output: `✓` = in sync, `✗` = drift (it says exactly what — missing, stale, or out of sync) — with
`--fix`, each `✗` gets repaired the same way `bootstrap.sh` would install it fresh.

**Reach for this whenever:**
- you just `git pull`ed the bundle and want to confirm the update actually took effect,
- you (or someone) edited a file under `tooling/commands/` directly and it doesn't seem to be
  reflected in your agent CLI,
- a `/pw-*` command errors, behaves oddly, or isn't recognized at all,
- you changed `pw.config.sh` (enabled/disabled a provider) and want to confirm the change landed.

`/pw-doctor` is the human-facing surface for this — it's the same underlying script
(`tooling/pw-doctor.sh`), but drive it through the command rather than calling the script directly.
`bootstrap.sh` and `offboard.sh` remain genuine exceptions — they run *before* any `/pw-*` command
is installed or *after* it's removed, so there's nothing else to invoke them through.

## Day-to-day

Read [README.md](./README.md) — the full guide. The loop, once onboarded:

```
/pw-new <slug>        scaffold a project         /pw-review <slug>     apply your review comments
/pw-analyze <slug>    context → analysis         /pw-execute <slug>    orchestrate worktree runs (commit + verify)
/pw-breakdown <slug>  analysis → PLAN + tasks     /pw-ship <slug>       push branches + open MRs (publish)
/pw-status <slug>     where am I / what's next    /pw-sync <slug>       refresh open MRs against a moved base
                                                  /pw-close <slug>      verify, tear down, learn
                                                  /pw-doctor [--fix]    check/repair install sync
                                                  /pw-rfc <slug>        optional — publish to an RFC doc
```

Each phase is **gated by your review** — an agent stops and you sign off before the next phase.
Only the **PLAN** sign-off is a hard gate for execution; per-task reviews are optional. `/pw-execute`
stops at *committed + verified* — nothing is pushed until you explicitly run `/pw-ship`. A bare
`/pw-execute <slug>` resumes everything outstanding in one invocation; `/pw-execute <slug> --wave`
runs only the immediately-ready tasks and checkpoints there instead — useful for chunking a long
plan (see [docs/EXECUTION.md](./docs/EXECUTION.md)).

## Memory (optional — not required)

The pipeline records decisions in each project's README + LOG regardless, so **it works with no
memory tool at all**. If you use one (EverOS, mem0, a notes repo, …), name it in `pw.config.sh`
(`PW_MEMORY` / `PW_MEMORY_NOTES`) and agents will search it at analysis and seed it at close-out; if
`PW_MEMORY=none` (the default), those steps are skipped silently and nothing blocks. Full guide,
including *why* you'd want one: **[docs/MEMORY.md](./docs/MEMORY.md)**.

## Register a new provider

**Two different meanings of "provider," worth separating up front:**
- An **Agent Provider** is the AI-agent CLI you actually run — `claude`, `kilo`, `opencode`, or a
  new one you're wiring up here. This section is about registering one of those.
- An **API Provider** is a narrower, different thing — which model *backend* a given Agent
  Provider talks to underneath (e.g. KiloCode alone can route to several: its own built-in `kilo`
  gateway, or `command_code`/`openrouter`/…). That's `PW_KILO_API_PROVIDERS` in `pw.config.sh`,
  unrelated to what follows.

**Is your CLI already `claude`, `kilo`, or `opencode`?** Those three are **built into**
`tooling/pw-common.sh` — you don't need anything below. Just add the name to `PW_PROVIDERS=(…)`
in `pw.config.sh` and re-run `./bootstrap.sh`. **Built-in is not the same as enabled** — a
built-in provider still does nothing until you list it in `PW_PROVIDERS` yourself; skip this
step and it's simply not wired up, whether or not the CLI is installed on your machine.

Registering a CLI that **isn't** one of those three is what the rest of this section covers. **You
don't edit any script** — everything goes in **`pw.config.sh`** (created for you on first
bootstrap; gitignored, so it stays yours):

1. Add its name to `PW_PROVIDERS=(…)`.
2. Define its **required** hooks in the same file (the scripts only supply defaults for the
   built-ins, so yours win — this is also why you should never redefine `claude_*`/`kilo_*`/
   `opencode_*` here: your version would silently replace the working built-in one):
   - `<name>_bin()` — the command to detect on `PATH`
   - `<name>_skilldir()` — where it reads skills (these are plain files/dirs, copied or
     symlinked as-is — no rendering involved)
   - `<name>_commanddir()` — where its generated slash-commands go
   - `render_<name>_command()` — **prints one finished command file to stdout.** Before calling
     it, `gen-commands.sh` sets four plain shell variables it inherits (no arguments are
     passed): `$desc` (one-line description), `$args` (argument hint, may be empty), `$agent`
     (optional provider-agent name, may be empty), `$bodytext` (the prompt body, with
     `{{PW_*}}` tokens already stamped to real paths, and `{{ARGS}}` still literal — map that to
     your CLI's own argument-placeholder syntax). Your function's only job is to `printf` the
     complete frontmatter + body to stdout — `gen-commands.sh` redirects that into the real
     file; the function itself never opens a file, and it never runs or invokes anything.
     Minimal shape (mirrors `render_claude_command` in `tooling/pw-common.sh`):
     ```sh
     render_myprov_command() {
       printf -- '---\ndescription: %s\n---\n%s' "$desc" "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
     }
     ```
3. *(Optional)* `<name>_agentdir()` + `render_<name>_agent()` to also seed the sub-agents
   (`pw-orchestrator`, `pw-executor`, `pw-reviewer`) for it. Same idea as `render_<name>_command`,
   but `gen-agents.sh` sets a different variable set beforehand: `$agentname` (the file's
   basename), `$desc`, `$displayName`, `$role`, `$claude_tools`, `$model`, `$bodytext` — see
   `render_claude_agent`/`render_kilo_agent` in `tooling/pw-common.sh` for full examples.
   Providers without these two hooks just skip agent-seeding — the `/pw-*` commands still work.
4. *(Optional)* `<name>_headless()` — prints the exact non-interactive invocation template for
   this CLI (e.g. an auto-approve flag, how the model/prompt gets passed), so an orchestrator
   running under a *different* provider can shell out to this one for cross-provider execution.
   See `claude_headless`/`kilo_headless`/`opencode_headless` in `tooling/pw-common.sh` for real
   examples. Without it, this provider is still fully usable same-provider — it just can't be a
   cross-provider execution **target**. Full mechanics: `tooling/docs/providers.md` (a
   maintainer-owned reference doc — you never edit it directly; this hook is the only thing you
   set).
5. Re-run `./bootstrap.sh`.

### Worked example: registering Cline

Say you want to add [Cline](https://cline.bot/cli)'s CLI (`npm i -g cline`; binary is just `cline`).
This is the shape of what goes in `pw.config.sh` — verify the exact frontmatter Cline's workflow
loader expects before relying on this, it's a starting point, not tested code:

```sh
PW_PROVIDERS+=(cline)

cline_bin()        { echo cline; }
cline_skilldir()   { echo "$HOME/.cline/skills"; }             # Cline's global skills dir
cline_commanddir() { echo "$HOME/Documents/Cline/Workflows"; } # global custom slash-commands ("workflows")

render_cline_command() {
  # Cline turns a workflow's FILENAME into its slash command (pw-new.md -> /pw-new) and only
  # reads a `description` frontmatter field — there's no {{ARGS}}-placeholder convention like
  # Claude's $ARGUMENTS, so the body just states "arguments follow the command" in prose instead
  # of substituting a token.
  printf -- '---\ndescription: %s\n---\n%s' "$desc" "${bodytext//\{\{ARGS\}\}/the arguments given}"
}

# OPTIONAL — only needed for cross-provider execution (an orchestrator on another provider
# handing a task to Cline headlessly). Skip this and Cline still works fully for same-provider use.
cline_headless() {
  cat <<'EOF'
cline "<prompt>" --yolo --json   (or piped: <prompt> | cline --yolo --json)
--yolo/--no-interactive auto-approves every action (required headless, same spirit as kilo's
--auto); --json gives structured output to scrape.
EOF
}
```

No `<name>_agentdir`/`render_<name>_agent` shown here either — skip those and Cline just won't
get the seeded sub-agents; the `/pw-*` commands still work.

Likewise, which KiloCode **API Providers** you use (default `kilo` itself; also `command_code`,
`openrouter`, … if you've added credentials for them — the model backend(s) KiloCode itself
connects to, a different axis from the Agent Provider list above) is just a list you set
(`PW_KILO_API_PROVIDERS=(…)`) in `pw.config.sh` — it never constrains a teammate. Reference any
of them in a task's `Execute with:` as `kilo:<provider>/<model>`.

## Offboarding / uninstalling

Leaving the team, decommissioning a machine, or just done with this pipeline? **`./offboard.sh`**
is the exact inverse of `./bootstrap.sh` — it removes the installed skill, generated `/pw-*`
commands, and seeded sub-agents per provider.

```bash
./offboard.sh                    # dry-run (default, always) — reports what WOULD be removed
./offboard.sh --yes              # actually remove it
./offboard.sh --provider kilo    # scope to one/more providers (comma-separated)
./offboard.sh --all-known        # also sweep claude/kilo even if no longer in PW_PROVIDERS —
                                  # catches files orphaned by disabling a provider in pw.config.sh
```

It only ever removes a file whose content **exactly matches** what this bundle would generate
right now (same check `pw-doctor.sh` uses) — anything you hand-edited, or a foreign file that
happens to share a name, is reported and skipped, never guessed at. It **never** touches
`pw.config.sh`, your scaffolded projects under `$PW_PROJECTS`, or this bundle's own folder — those
are yours; delete them yourself if you want a truly clean slate. See the script's own header
comment for the full safety contract.

## Notes for the maintainer (whoever shares this)

- **Keep the shipped skills in sync.** The bundle ships its own copies at
  `tooling/skill/project-workflow/SKILL.md` and `tooling/skill/pw-review/SKILL.md`. If you also
  maintain either elsewhere (e.g. a personal `ai-agent-dir`), refresh the bundle copy before
  committing/sharing: `cp <your-canonical>/SKILL.md tooling/skill/<name>/SKILL.md`.
- **`providers.md` is machine/account-specific config**, not code — model IDs and available
  providers differ per person. Treat the committed version as a sensible starting point; each
  person tunes their own.
- **Project dirs are not committed here.** This repo is the reusable bundle only; the
  `<slug>` projects you scaffold live in `$PW_PROJECTS` (the bundle's parent) and are yours.
