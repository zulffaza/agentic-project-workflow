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
  - **KiloCode** — `kilo`  (models via the `command_code` provider)
  - Something else? You can add it — see [Register a new provider](#register-a-new-provider).

## Onboard in 3 steps

```bash
# 1. Get the bundle. Convention: put it at <repos-root>/projects/base so it sits
#    ALONGSIDE the git repos you'll be changing.
git clone <bundle-remote> ~/IdeaProjects/projects/base     # or wherever you keep repos

# 2. Bootstrap: detects your CLIs, installs the skill + /pw-* commands for each,
#    writes pw-env.sh. Idempotent and non-destructive (won't clobber existing installs).
cd ~/IdeaProjects/projects/base
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
$PW_HOME/scaffold.sh demo      # scaffold a throwaway project
/pw-status demo                # your CLI should know the command and report phase=context
rm -rf $PW_PROJECTS/demo       # clean up
```

If `/pw-status` is recognized and prints a status, you're onboarded.

## What bootstrap did

- Resolved three path roots from the bundle's own location:
  `$PW_HOME` (this bundle) · `$PW_PROJECTS` (`$PW_HOME/..`, where projects go) ·
  `$PW_REPOS` (`$PW_PROJECTS/..`, where your git repos live).
- Installed the **`project-workflow` skill** into each detected CLI's skills dir (symlinked to
  `skill/project-workflow`, so bundle updates propagate).
- Generated the **`/pw-*` commands** for each detected CLI, with the real absolute paths stamped
  in (sources use `{{PW_*}}` tokens; the generator/scaffolder stamp them — that's the portability
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

Your CLI isn't `claude` or `kilo`? Two small edits make it a first-class provider — nothing
hard-codes the list:

1. **`bootstrap.sh`** → add its name to `PROVIDERS=(…)`, and define `<name>_bin()` (the command to
   look for on `PATH`) and `<name>_skilldir()` (where it reads skills).
2. **`workflow/gen-commands.sh`** → add its name to `PROVIDERS=(…)`, a `<name>_outdir()` (its
   commands dir), and a `render_<name>()` that prints a command file in its frontmatter format and
   maps the `{{ARGS}}` placeholder to its argument syntax.
3. **`workflow/providers.md`** → add a row: which models it runs and its **headless invocation**
   (how to run one task non-interactively). This is what cross-provider execution shells out to.
4. Re-run `./bootstrap.sh`.

## Notes for the maintainer (whoever shares this)

- **Keep the shipped skill in sync.** The bundle ships its own copy at
  `skill/project-workflow/SKILL.md`. If you also maintain the skill elsewhere (e.g. a personal
  `ai-agent-dir`), refresh the bundle copy before committing/sharing:
  `cp <your-canonical>/SKILL.md skill/project-workflow/SKILL.md`.
- **`providers.md` is machine/account-specific config**, not code — model IDs and available
  providers differ per person. Treat the committed version as a sensible starting roster; each
  person tunes their own.
- **Project dirs are not committed here.** This repo is the reusable `base/` bundle only; the
  `<slug>` projects you scaffold live in `$PW_PROJECTS` (the bundle's parent) and are yours.
