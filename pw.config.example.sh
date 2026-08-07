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

# --- KiloCode model providers (one OR MORE) ---------------------------------
# KiloCode can connect to several model providers at the same time — list every
# one you use. Reference any of them in a task's `Execute with:` as
# `kilo:<provider>/<model>` (e.g. `kilo:command_code/MiniMaxAI/MiniMax-M3`,
# `kilo:openrouter/anthropic/claude-3.5-sonnet`). The shipped examples in
# tooling/providers.md use `command_code`, but that's just the maintainer's
# setup — it does NOT constrain teammates who use different kilo providers.
PW_KILO_PROVIDERS=(command_code)
# Back-compat: the old singular PW_KILO_PROVIDER still works and is folded into
# PW_KILO_PROVIDERS automatically (see tooling/pw-common.sh). Prefer the array.

# --- Memory (OPTIONAL — the workflow never depends on it) -------------------
# The pipeline records decisions/learnings in each project's README + LOG regardless.
# If you use a memory tool, name it here and (optionally) describe how to use it; if not,
# leave "none" and agents skip all memory steps without blocking. See tooling/memory.md.
#   PW_MEMORY="none"          # "none" (default) | "everos" | "mem0" | your tool's short name
#   PW_MEMORY_NOTES=""        # free text: buckets/scopes/how the agent should search+seed it
PW_MEMORY="none"
PW_MEMORY_NOTES=""

# --- Git forge host overrides (OPTIONAL — auto-detect covers github.com/gitlab.com) ---------
# /pw-ship and /pw-adopt resolve which CLI (gh/glab) talks to a repo from its OWN origin remote
# host — see tooling/forges.md. Public github.com/gitlab.com need ZERO config. Only a self-hosted
# GitLab (or any forge needing a host env var) needs an override here:
#   PW_FORGE_HOSTS=("git.internal.example.com=gitlab")
PW_FORGE_HOSTS=()

# --- RFC publishing (OPTIONAL — default "markdown" needs no external tool at all) -----------
# /pw-rfc always generates <project>/rfc/RFC.md locally, regardless of backend. Publishing that
# to an external doc platform is additional and opt-in — see tooling/rfc.md + tooling/rfc-backends.md.
#   PW_RFC_BACKEND="markdown"   # "markdown" (default, zero-dependency) | "lark" | (stub only) confluence/google-docs/notion
#   PW_RFC_LARK_TEMPLATE=""     # Lark doc/wiki template token or URL — only used when backend=lark
#   PW_RFC_LARK_SPACE=""        # default target wiki space/parent-node token (or set per-project via /pw-rfc --target)
#   PW_RFC_NOTES=""             # freeform notes, same spirit as PW_MEMORY_NOTES
PW_RFC_BACKEND="markdown"
PW_RFC_LARK_TEMPLATE=""
PW_RFC_LARK_SPACE=""
PW_RFC_NOTES=""

# --- Onboard a brand-new provider without touching the scripts --------------
# Add its name to PW_PROVIDERS above, then define its four command hooks here:
#   myprov_bin()      { echo myprov-cli; }               # command to detect on PATH
#   myprov_skilldir() { echo "$HOME/.myprov/skills"; }   # where it reads skills
#   myprov_outdir()   { echo "$HOME/.myprov/commands"; } # where its slash-commands go
#   render_myprov()   { … }  # print one command file (see render_claude/render_kilo)
#
# OPTIONAL — to also seed the sub-agents (pw-orchestrator, pw-executor) for it, add:
#   myprov_agentdir()     { echo "$HOME/.myprov/agents"; }  # where it reads sub-agents
#   render_myprov_agent() { … }  # print one agent file (see render_claude_agent/render_kilo_agent)
# Providers without these two hooks just skip agent-seeding — commands still work.
