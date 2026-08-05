# shellcheck shell=bash
# ============================================================================
# pw.config — your LOCAL configuration for the project-workflow pipeline.
#
# This is the one file you edit. `bootstrap.sh` and `tooling/gen-commands.sh`
# SOURCE it — you never edit those scripts to change which providers you use.
#
# On first run, bootstrap.sh copies this to `pw.config.sh` (gitignored), so your
# machine/account-specific choices stay out of the shared repo. Edit pw.config.sh.
# ============================================================================

# --- Which agent CLIs to wire up --------------------------------------------
# List ONLY the CLIs you actually use; others are ignored even if installed.
# Known out of the box: claude (Claude Code), kilo (KiloCode).
# Example — someone who only uses KiloCode would set: PW_PROVIDERS=(kilo)
PW_PROVIDERS=(claude kilo)

# --- Optional per-provider overrides ----------------------------------------
# Define any of these to override a built-in default; omit to keep the default.
# (Functions defined here win — the scripts only set a default if you didn't.)
#
#   # if your kilo build reads skills from a different dir:
#   kilo_skilldir() { echo "$HOME/.kilocode/skills"; }
#   # if the binary is named differently on your PATH:
#   kilo_bin()      { echo kilo; }

# --- KiloCode model provider (your choice) ----------------------------------
# KiloCode can connect to many model providers. The shipped examples in
# tooling/providers.md happen to use `command_code`, but that's just the
# maintainer's setup — set yours here and use it in your task `Execute with:`
# lines. It does NOT constrain teammates who use a different kilo provider.
PW_KILO_PROVIDER="command_code"

# --- Memory (OPTIONAL — the workflow never depends on it) -------------------
# The pipeline records decisions/learnings in each project's README + LOG regardless.
# If you use a memory tool, name it here and (optionally) describe how to use it; if not,
# leave "none" and agents skip all memory steps without blocking. See tooling/memory.md.
#   PW_MEMORY="none"          # "none" (default) | "everos" | "mem0" | your tool's short name
#   PW_MEMORY_NOTES=""        # free text: buckets/scopes/how the agent should search+seed it
PW_MEMORY="none"
PW_MEMORY_NOTES=""

# --- Onboard a brand-new provider without touching the scripts --------------
# Add its name to PW_PROVIDERS above, then define its four hooks here:
#   myprov_bin()      { echo myprov-cli; }               # command to detect on PATH
#   myprov_skilldir() { echo "$HOME/.myprov/skills"; }   # where it reads skills
#   myprov_outdir()   { echo "$HOME/.myprov/commands"; } # where its slash-commands go
#   render_myprov()   { … }  # print one command file (see render_claude/render_kilo)
