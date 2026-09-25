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
  `/pw-adopt` need one per repo.
- At least one supported Agent Provider (AI-agent CLI) on your `PATH` — built in, no extra config:
  - **Claude Code** — `claude`
  - **KiloCode** — `kilo`  (KiloCode connects to many model API Providers; you pick which one(s)
    in `pw.config.sh` — the shipped default is `kilo` itself, KiloCode's own built-in gateway,
    which needs no separate credential; `command_code`/`openrouter`/etc. shown elsewhere as
    examples are just the maintainer's own additional setup, not a requirement)
  - **OpenCode** — `opencode`
  - **Cursor CLI** — `agent`  (its own single model gateway — no API-Provider axis; ids
    come from `agent models`)
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

Forget the syntax? `/pw-help` renders the live how-to — every command and operator with its exact
arguments, plus `/pw-help project <slug>` for what to run right now and `/pw-help find <term>`
to locate a concept across the tooling surface. It reads the live bundle, so it cannot go stale.

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
- Installed every shipped **skill** (`project-workflow`, `pw-review` — the standalone fresh-review
  method behind the optional AI-assisted review feature — and `pw-rfc`, the RFC-authoring guide)
  into each enabled+detected CLI's skills dir (linked to the bundle, so bundle
  updates propagate).
- Generated the **`/pw-*` commands** for each enabled+detected CLI, with the real absolute paths
  stamped in (sources use `{{PW_*}}` tokens; the generator/scaffolder stamp them — the portability
  trick).
- Seeded the **sub-agents** (`pw-orchestrator`, `pw-executor`, and `pw-reviewer` — optional, off by
  default per project/phase) into each CLI's agent dir the same way.
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
(`project-workflow`, `pw-review`, `pw-rfc`) is installed and matches the bundle; every generated `/pw-*`
command file matches its canonical source in the bundle; the seeded sub-agents match too. Reading the
output: `✓` = in sync, `✗` = drift (it says exactly what — missing, stale, or out of sync) — with
`--fix`, each `✗` gets repaired the same way `bootstrap.sh` would install it fresh.

**Reach for this whenever:**
- you just `git pull`ed the bundle and want to confirm the update actually took effect,
- you (or someone) edited a command's canonical source in the bundle and it doesn't seem to be
  reflected in your agent CLI,
- a `/pw-*` command errors, behaves oddly, or isn't recognized at all,
- you changed `pw.config.sh` (enabled/disabled a provider) and want to confirm the change landed.

`/pw-doctor` is the human-facing surface for this — one underlying script in the bundle backs it,
but drive it through the command rather than calling the script directly.
`bootstrap.sh` and `offboard.sh` remain genuine exceptions — they run *before* any `/pw-*` command
is installed or *after* it's removed, so there's nothing else to invoke them through.

## Day-to-day

Read [README.md](./README.md) — the full guide. The loop, once onboarded:

```
/pw-new <slug>        scaffold a project         /pw-review <slug>     apply your review comments
/pw-analyze <slug>    context → analysis         /pw-execute <slug>    orchestrate worktree runs (commit + verify)
/pw-breakdown <slug>  analysis → PLAN + tasks     /pw-ship <slug>       push branches + open MRs (publish)
/pw-status <slug>     where am I / what's next    /pw-sync <slug>       refresh open MRs against a moved base
/pw-context <slug>    edit context docs           /pw-close <slug>      verify, tear down, learn
  (req-init · add-input · add-repo)               /pw-doctor [--fix]    check/repair install sync
                                                  /pw-rfc <slug>        optional — publish to an RFC doc
/pw-help                how-to map: commands, operators, exact args, next steps for a project
```

`/pw-review` also takes write operators so you never hand-copy review-file blocks:
`/pw-review <slug> init-all` (create every missing review file), `… item <path> §4 <ask>` (add an
item), `… answer <path> Q2 <text>` (answer a question), `… signoff <path> approved` (your gate
row) — see [docs/REVIEW.md](./docs/REVIEW.md).

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
- An **Agent Provider** is the AI-agent CLI you actually run — `claude`, `kilo`, `opencode`,
  `cursor`, or a new one you're wiring up here. This section is about registering one of those.
- An **API Provider** is a narrower, different thing — which model *backend* a given Agent
  Provider talks to underneath (e.g. KiloCode alone can route to several: its own built-in `kilo`
  gateway, or `command_code`/`openrouter`/…). That's `PW_KILO_API_PROVIDERS` in `pw.config.sh`,
  unrelated to what follows. Entries are **model-id prefix filters** (slashes allowed — a BYOK
  registered under the gateway is scoped as `kilo/alibaba-token-plan` and addressed as
  `kilo:kilo/alibaba-token-plan/<model>`; the prefix-less form names a *direct* provider line
  instead — the `kilo/` prefix distinguishes the two connections), never `kilo models` query
  arguments.

**Provider independence.** Every provider's install must be **self-contained in its own
  dirs** — `pw.env.sh`-style shared config aside, one provider never reads or depends on another
  provider's install surface. Some vendor CLIs *additionally* glob other vendors' config dirs as a
  compat fallback (Cursor reads `~/.claude/{skills,agents}`); that is unmanaged **bleed**, not
  contract — never build on it, and `/pw-doctor` flags it informationally. A provider's hooks,
  generated files, and runtime behavior must survive another provider's install or removal entirely.

**Is your CLI already `claude`, `kilo`, `opencode`, or `cursor`?** Those four are **built into**
the bundle — you don't need anything below. Just add the name to `PW_PROVIDERS=(…)`
in `pw.config.sh` and re-run `./bootstrap.sh`. **Built-in is not the same as enabled** — a
built-in provider still does nothing until you list it in `PW_PROVIDERS` yourself; skip this
step and it's simply not wired up, whether or not the CLI is installed on your machine.

Registering a CLI that **isn't** one of those four is still **no script editing** — everything goes
in **`pw.config.sh`** (gitignored, so it stays yours): add its name to `PW_PROVIDERS=(…)`, then
define its provider hooks there (detect binary, install dirs, renderer functions). The hook
contract, the built-in reference implementations, and a worked registration example live with the
machinery — [docs/TOOLING.md](./docs/TOOLING.md) pins the exact file. Providers without the
optional hooks still work fully same-provider; only cross-provider execution needs the extra hook.
Re-run `./bootstrap.sh` after registering.

Likewise, which KiloCode **API Providers** you use (default `kilo` itself; also `command_code`,
`openrouter`, … if you've added credentials for them — the model backend(s) KiloCode itself
connects to, a different axis from the Agent Provider list above) is just a list you set
(`PW_KILO_API_PROVIDERS=(…)`) in `pw.config.sh` — it never constrains a teammate. Reference any
of them in a task's `Execute with:` as `kilo:<provider>/<model>`; a BYOK registered *under* the
gateway uses its catalog path (`kilo:kilo/alibaba-token-plan/<model>`, entry
`kilo/alibaba-token-plan`) — matching is exact-first, so the prefix-less
`kilo:alibaba-token-plan/<model>` binds a *direct* provider line when one exists.
The same prefix-filter axis is generic — `PW_OPENCODE_API_PROVIDERS=(…)` works identically for
opencode; cursor (one gateway) and claude (fixed aliases) have no API-Provider axis.

## Offboarding / uninstalling

Leaving the team, decommissioning a machine, or just done with this pipeline? **`./offboard.sh`**
is the exact inverse of `./bootstrap.sh` — it removes the installed skill, generated `/pw-*`
commands, and seeded sub-agents per provider.

```bash
./offboard.sh                    # dry-run (default, always) — reports what WOULD be removed
./offboard.sh --yes              # actually remove it
./offboard.sh --provider kilo    # scope to one/more providers (comma-separated)
./offboard.sh --all-known        # also sweep ALL built-ins (claude, kilo, opencode, cursor)
                                 # even if no longer in PW_PROVIDERS —
                                  # catches files orphaned by disabling a provider in pw.config.sh
```

It only ever removes a file whose content **exactly matches** what this bundle would generate
right now (the same check `/pw-doctor` uses) — anything you hand-edited, or a foreign file that
happens to share a name, is reported and skipped, never guessed at. It **never** touches
`pw.config.sh`, your scaffolded projects under `$PW_PROJECTS`, or this bundle's own folder — those
are yours; delete them yourself if you want a truly clean slate. See the script's own header
comment for the full safety contract.

## A note about where things live

This repo is the reusable **bundle** only. The `<slug>` projects you scaffold live in
`$PW_PROJECTS` (the bundle's parent) and are yours — they are never committed here. The bundle
directory itself holds the docs you're reading plus the machinery the `/pw-*` commands call;
curious about the machinery? [docs/TOOLING.md](./docs/TOOLING.md).
