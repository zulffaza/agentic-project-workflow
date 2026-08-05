# Onboarding — the agentic project-workflow pipeline

This bundle is a **phased, multi-repo AI-agent workflow**: gather context → analyze → break into
tasks → execute in isolated git worktrees → review → learn. You drive it with `/pw-*` slash
commands from your agent CLI. It's provider-agnostic — it works with whatever AI coding CLI you
have (Claude Code, KiloCode, …), and you only get wired up for the ones you actually have.

Same steps whether you're a **new teammate** or **recovering a wiped machine**.

## Prerequisites

- `git`, `bash`, `perl` (all standard on macOS/Linux).
- At least one supported agent CLI on your `PATH`:
  - **Claude Code** — `claude`
  - **KiloCode** — `kilo`  (KiloCode connects to many model providers; you pick which one in
    `pw.config.sh` — the shipped examples use `command_code`, but that's just one choice)
  - Something else? You can add it — see [Register a new provider](#register-a-new-provider).

## Onboard in 3 steps

```bash
# 1. Clone the bundle so it sits ALONGSIDE the git repos you'll be changing —
#    i.e. inside your repos root (the default $PW_REPOS is two levels up).
git clone <remote-url>/agentic-project-workflow ~/IdeaProjects/projects/agentic-project-workflow
cd ~/IdeaProjects/projects/agentic-project-workflow

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
$PW_HOME/tooling/scaffold.sh demo      # scaffold a throwaway project
/pw-status demo                # your CLI should know the command and report phase=context
rm -rf $PW_PROJECTS/demo       # clean up
```

If `/pw-status` is recognized and prints a status, you're onboarded.

## What bootstrap did

- Created `pw.config.sh` from `pw.config.example.sh` (first run only) and read `PW_PROVIDERS`
  from it — the CLIs you enabled.
- Resolved three path roots from the bundle's own location:
  `$PW_HOME` (this bundle) · `$PW_PROJECTS` (`$PW_HOME/..`, where projects go) ·
  `$PW_REPOS` (`$PW_PROJECTS/..`, where your git repos live).
- Installed the **`project-workflow` skill** into each enabled+detected CLI's skills dir (symlinked
  to `tooling/skill/project-workflow`, so bundle updates propagate).
- Generated the **`/pw-*` commands** for each enabled+detected CLI, with the real absolute paths
  stamped in (sources use `{{PW_*}}` tokens; the generator/scaffolder stamp them — the portability
  trick).
- Wrote `pw-env.sh`.

Re-run `./bootstrap.sh` any time (e.g. after `git pull`). Use `--force` to re-link the skill,
`--check` to detect-and-report without changing anything.

## Day-to-day

Read [README.md](./README.md) — the full guide. The loop, once onboarded:

```
/pw-new <slug>        scaffold a project        /pw-review <slug>     apply your review comments
/pw-analyze <slug>    context → analysis        /pw-execute <slug>    orchestrate worktree runs
/pw-breakdown <slug>  analysis → PLAN + tasks    /pw-close <slug>      verify, tear down, learn
/pw-status <slug>     where am I / what's next
```

Each phase is **gated by your review** — an agent stops and you sign off before the next phase.

## Register a new provider

Your CLI isn't `claude` or `kilo`? **You don't edit any script** — everything goes in
**`pw.config.sh`** (created for you on first bootstrap; gitignored, so it stays yours):

1. Add its name to `PW_PROVIDERS=(…)`.
2. Define its four hooks in the same file (the scripts only supply defaults for the built-ins, so
   yours win):
   - `<name>_bin()` — the command to detect on `PATH`
   - `<name>_skilldir()` — where it reads skills
   - `<name>_outdir()` — where its slash-commands go
   - `render_<name>()` — prints one command file in its frontmatter format, mapping the `{{ARGS}}`
     placeholder to its argument syntax (copy `render_claude`/`render_kilo` from
     `tooling/gen-commands.sh` as a starting point)
3. Add a row to [`tooling/providers.md`](./tooling/providers.md): which models it runs and its
   **headless invocation** (how to run one task non-interactively) — what cross-provider execution
   shells out to.
4. Re-run `./bootstrap.sh`.

Likewise, which KiloCode **model provider** you use (`command_code` or anything else) is just a
value you set (`PW_KILO_PROVIDER`) in `pw.config.sh` — it never constrains a teammate.

## Notes for the maintainer (whoever shares this)

- **Keep the shipped skill in sync.** The bundle ships its own copy at
  `tooling/skill/project-workflow/SKILL.md`. If you also maintain the skill elsewhere (e.g. a
  personal `ai-agent-dir`), refresh the bundle copy before committing/sharing:
  `cp <your-canonical>/SKILL.md tooling/skill/project-workflow/SKILL.md`.
- **`providers.md` is machine/account-specific config**, not code — model IDs and available
  providers differ per person. Treat the committed version as a sensible starting roster; each
  person tunes their own.
- **Project dirs are not committed here.** This repo is the reusable `base/` bundle only; the
  `<slug>` projects you scaffold live in `$PW_PROJECTS` (the bundle's parent) and are yours.
