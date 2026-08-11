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

# --- Which Agent Providers to wire up ---------------------------------------
# An "Agent Provider" is the AI-agent CLI you actually run (claude, kilo, opencode, …) — not
# to be confused with an "API Provider" (see the KiloCode section below), which is a different,
# narrower concept: which model BACKEND a given Agent Provider talks to underneath.
#
# Built-in (claude, kilo, opencode) means the hooks already exist in tooling/pw-common.sh — you
# never write bin/skilldir/commanddir/render_* functions for these. But "built-in" is NOT the
# same as "enabled": you still list a provider's name here yourself for it to become active.
# List ONLY the CLIs you actually use; others are ignored even if installed.
# Example — someone who only uses KiloCode would set: PW_PROVIDERS=(kilo)
PW_PROVIDERS=(claude)

# --- Optional per-provider overrides ----------------------------------------
# Define any of these to override a built-in default; omit to keep the default.
# (Functions defined here win — the scripts only set a default if you didn't.)
#
#   # if your kilo build reads skills from a different dir:
#   kilo_skilldir() { echo "$HOME/.kilocode/skills"; }
#   # if the binary is named differently on your PATH:
#   kilo_bin()      { echo kilo; }

# --- KiloCode API Providers (one OR MORE) -----------------------------------
# KiloCode (an Agent Provider) can connect to several model API Providers at the same time —
# list every one you use. An "API Provider" here means the model BACKEND kilo talks to
# (kilo, command_code, openrouter, …) — a different axis from PW_PROVIDERS above, which is
# about the CLI itself. Default here is "kilo" — KiloCode's own built-in gateway, which needs no
# separate credential (unlike command_code/openrouter/etc., each its own paid API key).
#
# How to check what's available on YOUR machine:
#   kilo auth list            # your configured credentials, by DISPLAY NAME (e.g. "Kilo Gateway")
#   kilo models                # every model across every configured provider, as <id>/<model>
#   kilo models <provider-id>  # filter to just one provider
#
# How to write the provider id: use the string that appears BEFORE the first "/" in `kilo
# models`' output — NOT necessarily the display name `kilo auth list` shows. These can differ:
# the credential displayed as "Kilo Gateway" actually resolves under the id `kilo` (confirmed —
# `kilo models kilo_gateway` errors "Provider not found", `kilo models kilo` works). Always
# sanity-check a new id with `kilo models <id>` before using it in PW_KILO_API_PROVIDERS or a
# task's `Execute with:` — don't guess from the display name alone.
#
# Reference any provider you've listed in a task's `Execute with:` as `kilo:<provider>/<model>`
# (e.g. `kilo:kilo/anthropic/claude-opus-5`, `kilo:command_code/MiniMaxAI/MiniMax-M3`).
# The shipped examples in tooling/docs/providers.md use `command_code`, but that's just the
# maintainer's own verified setup — it does NOT constrain teammates who use a different one.
PW_KILO_API_PROVIDERS=(kilo)
# Back-compat: the old names PW_KILO_PROVIDERS (array) and PW_KILO_PROVIDER (singular) still
# work and are folded into PW_KILO_API_PROVIDERS automatically (see tooling/pw-common.sh).
# Prefer PW_KILO_API_PROVIDERS going forward.

# --- Memory (OPTIONAL — the workflow never depends on it) -------------------
# The pipeline records decisions/learnings in each project's README + LOG regardless.
# If you use a memory tool, name it here and (optionally) describe how to use it; if not,
# leave "none" and agents skip all memory steps without blocking. See tooling/docs/memory.md.
#   PW_MEMORY="none"          # "none" (default) | "everos" | "mem0" | your tool's short name
#   PW_MEMORY_NOTES=""        # free text: buckets/scopes/how the agent should search+seed it
PW_MEMORY="none"
PW_MEMORY_NOTES=""

# --- Model allowlist (OPTIONAL — a guard against an agent picking an unexpectedly expensive
# model, not a routing mechanism) --------------------------------------------
# THE RULE: empty or unset (the default, shown below) = ALL models allowed for that provider.
# Nothing is restricted unless you explicitly set a pattern here yourself — an agent or you can
# still pick any model freely. Set one only if you specifically want to rule some OUT.
# Comma-separated glob patterns, matched against the model id — i.e. everything AFTER the
# provider prefix in `Execute with: <provider>:<model-id>` (e.g. "sonnet", or
# "command_code/deepseek/*"). /pw-breakdown checks a task's chosen model against this when
# filling `Execute with:`; /pw-execute checks again right before running it (catches a
# hand-edited task file too). Checking whether your configured patterns actually MATCH anything
# real — never by hand — is what `/pw-doctor` is for; see its "Model availability" section.
#   PW_MODEL_ALLOWLIST_CLAUDE=""     # e.g. "sonnet,haiku" — Claude Code has a fixed alias set,
#                                    # not a queryable catalog, so pw-doctor can't verify these
#                                    # against a live list (see docs/EXECUTION.md).
#   PW_MODEL_ALLOWLIST_KILO=""       # e.g. "command_code/deepseek/*,kilo/anthropic/claude-haiku*"
#   PW_MODEL_ALLOWLIST_OPENCODE=""   # e.g. "anthropic/claude-haiku*"
PW_MODEL_ALLOWLIST_CLAUDE=""
PW_MODEL_ALLOWLIST_KILO=""
PW_MODEL_ALLOWLIST_OPENCODE=""

# --- AI-assisted review (OPTIONAL — off leaves today's human-only review unchanged) ----------
# Every scaffolded project gets a per-phase "AI Review" dashboard line (off|advisory|auto for each
# of analysis/plan/task-plan/task-exec/ship), seeded from this ONE bundle-wide default and then
# freely overridable per project/phase any time via `/pw-review <slug> config <phase> <mode>` —
# see docs/REVIEW.md. This only changes what NEW projects are scaffolded with; it never touches an
# already-scaffolded project's dashboard.
#   PW_AI_REVIEW_DEFAULT="off"   # "off" (default) | "advisory" | "auto"
PW_AI_REVIEW_DEFAULT="off"

# --- Git forge host overrides (OPTIONAL — auto-detect covers github.com/gitlab.com) ---------
# /pw-ship and /pw-adopt resolve which CLI (gh/glab) talks to a repo from its OWN origin remote
# host — see tooling/docs/forges.md. Public github.com/gitlab.com need ZERO config. Only a self-hosted
# GitLab (or any forge needing a host env var) needs an override here:
#   PW_FORGE_HOSTS=("git.internal.example.com=gitlab")
PW_FORGE_HOSTS=()

# --- RFC publishing (OPTIONAL — default "markdown" needs no external tool at all) -----------
# /pw-rfc always generates <project>/rfc/RFC.md locally, regardless of backend. Publishing that
# to an external doc platform is additional and opt-in — see tooling/docs/rfc.md + tooling/docs/rfc-backends.md.
#   PW_RFC_BACKEND="markdown"   # "markdown" (default, zero-dependency) | "lark" | (stub only) confluence/google-docs/notion
#   PW_RFC_LARK_TEMPLATE=""     # Lark doc/wiki template token or URL — only used when backend=lark
#   PW_RFC_LARK_SPACE=""        # default target wiki space/parent-node token (or set per-project via /pw-rfc --target)
#   PW_RFC_NOTES=""             # freeform notes, same spirit as PW_MEMORY_NOTES
PW_RFC_BACKEND="markdown"
PW_RFC_LARK_TEMPLATE=""
PW_RFC_LARK_SPACE=""
PW_RFC_NOTES=""

# --- Onboard a brand-new Agent Provider without touching the scripts --------
# First check: is your CLI already claude, kilo, or opencode? Those are built into
# tooling/pw-common.sh — just add the name to PW_PROVIDERS above, nothing else. Everything
# below is ONLY for a CLI that ISN'T on that list — don't redefine a built-in provider's hooks
# here, since a function you define in this file always wins over the built-in default, and a
# well-meaning but incomplete redefinition would silently replace one that already works.
#
# Add its name to PW_PROVIDERS above, then define its REQUIRED hooks here:
#   myprov_bin()        { echo myprov-cli; }               # command to detect on PATH
#   myprov_skilldir()   { echo "$HOME/.myprov/skills"; }   # where it reads skills
#   myprov_commanddir() { echo "$HOME/.myprov/commands"; } # where its slash-commands go
#   render_myprov_command() { … }   # prints ONE finished command file to stdout — see below
#
# render_myprov_command() is called once per canonical file in tooling/commands/*.md. Before
# calling it, gen-commands.sh sets these plain shell variables (it inherits them — no arguments
# are passed): $desc (one-line description) $args (argument hint, may be empty) $agent (optional
# provider-agent name, may be empty) $bodytext (the prompt body, with {{PW_*}} tokens already
# stamped to real paths). Your function's ONLY job is to `printf`/`echo` the complete file
# content — frontmatter + body — to stdout; gen-commands.sh redirects that into the real file.
# A minimal example, mirroring render_claude_command in tooling/pw-common.sh:
#   render_myprov_command() {
#     printf -- '---\ndescription: %s\n---\n%s' "$desc" "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
#   }
#
# OPTIONAL — to also seed the sub-agents (pw-orchestrator, pw-executor, pw-reviewer) for it, add:
#   myprov_agentdir()     { echo "$HOME/.myprov/agents"; }  # where it reads sub-agents
#   render_myprov_agent() { … }  # same idea, but gen-agents.sh sets $agentname $desc
#                                # $displayName $role $claude_tools $model $bodytext instead —
#                                # see render_claude_agent/render_kilo_agent for full examples.
# Providers without these two hooks just skip agent-seeding — commands still work.
