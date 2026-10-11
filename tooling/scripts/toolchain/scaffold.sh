#!/usr/bin/env bash
# Scaffold a new agentic-workflow project from template/.
# Usage: tooling/scripts/toolchain/scaffold.sh --project <project-slug>
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # tooling/
PW_HOME="$(cd "$HERE/../../.." && pwd)"                       # repo root (the bundle)
TEMPLATE_DIR="$PW_HOME/template"                        # what a project is made of

# Three roots for stamping {{PW_*}} tokens into copied templates (see gen-commands.sh).
PW_PROJECTS="${PW_PROJECTS:-$(cd "$PW_HOME/.." && pwd)}"
PW_REPOS="${PW_REPOS:-$(cd "$PW_PROJECTS/.." && pwd)}"

# Shared plumbing — this is the single place that loads pw.config.sh (fallback: the example), so
# PW_AI_REVIEW_DEFAULT below always reflects the same config bootstrap.sh/gen-commands.sh/
# pw-doctor.sh see, never a second, drifting copy of that fallback logic.
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"
AI_REVIEW_PHASES="context analysis plan task-plan task-exec ship rfc close"
# New rows start advisory (a legacy env floor of `off` normalizes — an explicit /pw-review … ai
# request must never be silently dead; the removed `off` value is not a write target anymore).
review_default="${PW_AI_REVIEW_DEFAULT:-advisory}"
case "$review_default" in advisory|auto) ;; *) review_default="advisory" ;; esac
ai_review_default_line=""
for p in $AI_REVIEW_PHASES; do ai_review_default_line="$ai_review_default_line $p=$review_default"; done
ai_review_default_line="${ai_review_default_line# }"
# Scheduling/repair/budget floors: manual/manual/3 — completion review and bounded repair are
# opt-in per project; the bounded cycle allows at most two intervening verified repairs.
review_trigger_default_line=""
review_repair_default_line=""
for p in $AI_REVIEW_PHASES; do
  review_trigger_default_line="$review_trigger_default_line $p=manual"
  review_repair_default_line="$review_repair_default_line $p=manual"
done
review_trigger_default_line="${review_trigger_default_line# }"
review_repair_default_line="${review_repair_default_line# }"
review_budget_default_line="rounds=3"
# spawn-lane model rows (docs/EXECUTION.md §Spawning phase work) — every lane defaults unbound
# (`—` = provider's own default), same config-driven shape as the AI Review line above.
AI_MODEL_ROLES="researcher analyst writer-task reviewer verifier"
ai_model_default_line=""
for r in $AI_MODEL_ROLES; do
  rv="$(printf '%s' "$r" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
  _rv_var="PW_AI_MODEL_DEFAULT_${rv}"
  rv_val="${!_rv_var:-—}"
  ai_model_default_line="$ai_model_default_line $r=$rv_val"
done
ai_model_default_line="${ai_model_default_line# }"


slug=""
while [ $# -gt 0 ]; do
  a="$1"; shift; v=""
  case "$a" in --project=*) v="${a#*=}"; a="--project" ;; esac
  case "$a" in
    --project) [ -n "$v" ] || { [ $# -ge 1 ] || { echo "Usage: $(basename "$0") --project <project-slug>   (e.g. spring-boot-3-upgrade)" >&2; exit 1; }; v="$1"; shift; }; slug="$v" ;;
    -*) echo "Error: unknown option: $a  (name the project: --project <slug>)" >&2; exit 1 ;;
    *) echo "Error: unexpected argument: $a  (name the project: --project <slug>)" >&2; exit 1 ;;
  esac
done
if [[ -z "$slug" ]]; then
  echo "Usage: $(basename "$0") --project <project-slug>   (e.g. spring-boot-3-upgrade)" >&2
  exit 1
fi
if [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Error: use a kebab-case slug (lowercase, digits, hyphens): got '$slug'" >&2
  exit 1
fi

dest="$PW_PROJECTS/$slug"
if [[ -e "$dest" ]]; then
  echo "Error: $dest already exists." >&2
  exit 1
fi

# Format before creating anything; Created and LOG describe the same event.
created="$(pw_now_wib)" || { echo "scaffold: cannot format event timestamp → fix: check the date command and retry" >&2; exit 1; }

# Copy the template tree (dashboard template is rendered separately, below).
mkdir -p "$dest"
rsync -a \
  --exclude '/PROJECT.template.md' \
  --exclude '.DS_Store' \
  "$TEMPLATE_DIR"/ "$dest"/

# Render the project dashboard as the project's README.md. Bash string replacement, never a
# sed program string: the config-derived default lines are data (a `|` in a config value
# must not terminate a sed s-command or reach GNU-sed's `e`).
while IFS= read -r _rl || [ -n "$_rl" ]; do
  _rl="${_rl//<PROJECT_NAME>/$slug}"
  _rl="${_rl//<CREATED>/$created}"
  _rl="${_rl//<AI_REVIEW_DEFAULT>/$ai_review_default_line}"
  _rl="${_rl//<REVIEW_TRIGGER_DEFAULT>/$review_trigger_default_line}"
  _rl="${_rl//<REVIEW_REPAIR_DEFAULT>/$review_repair_default_line}"
  _rl="${_rl//<REVIEW_BUDGET_DEFAULT>/$review_budget_default_line}"
  _rl="${_rl//<AI_MODELS_DEFAULT>/$ai_model_default_line}"
  printf '%s\n' "$_rl"
done < "$TEMPLATE_DIR/PROJECT.template.md" > "$dest/README.md"

# Stamp {{PW_*}} tokens (absolute paths) into every copied markdown file. Shared helper —
# bash replacement + pw_tmpfile staging; install paths never become perl program text.
find "$dest" -type f -name '*.md' -print0 | while IFS= read -r -d '' md; do
  pw_stamp_tokens "$md" || { echo "scaffold: token stamping failed for $md" >&2; exit 1; }
done

# Keep empty phase dirs present even if rsync left them out; add the review/ subdirs.
# (No per-project sub-agent/ dir — reusable agents are seeded from tooling/agents/ via bootstrap.)
mkdir -p "$dest/context" "$dest/analysis/review" "$dest/task/review" "$dest/worktree"

# Seed the append-only activity log.
cat > "$dest/LOG.md" <<LOGEOF
# Activity log — $slug

Append-only audit trail. One line per meaningful action: phase transitions, sub-agent spawns,
commits, pushes, MRs, review passes, close-out. Newest at the bottom. The /pw-* commands append
here automatically (via pw-status.sh log --project <slug> --actor <a> --message <text…> — never
hand-edit); add manual notes the same way, or as
another Markdown bullet, so it reads consistently in preview.

Format: a bullet per entry — "- **DD MMMM YYYY - HH.mm WIB** · \`<phase/actor>\` — <what happened>"

- **$created** · \`scaffold\` — project created
LOGEOF

cat <<EOF
Created $dest

Structure:
  README.md         dashboard — Status field + task table + MR table (commands keep it current)
  LOG.md            append-only audit trail
  context/          drop inputs here, log each in context/INDEX.md
    INDEX.md          provenance table + "repos in scope" first guess
  analysis/         agent writes analysis here (from analysis/_TEMPLATE.md)
    review/           your analysis review files (<topic>.review.md)
  task/             PLAN.md + T0n.md tasks (from task/_TEMPLATE-*.md)
    review/           your plan/task review files (PLAN.review.md, T0n.review.md)
  worktree/         isolated worktrees appear here during execution
  rfc/              optional — /pw-rfc's side-loop lives here (RFC.md/META.md appear on first run)

Next steps (each phase is gated by your review):
  1. Add inputs to $dest/context/ (tickets, RFC excerpts, code refs). Optionally start a one-page
     brief: cp $dest/context/_REQUIREMENTS.template.md $dest/context/REQUIREMENTS.md and fill it.
  2. Fill context/INDEX.md — a row per input (what it is + where it came from), and your
     first-guess "repos in scope" table.
  3. /pw-analyze --project $slug        → writes analysis/ + auto-creates analysis/review/<topic>.review.md,
     sets Status=analysis. Add items to that review file, /pw-review --project $slug, sign off when satisfied.
  4. /pw-breakdown --project $slug      → writes task/PLAN.md + T0n.md + auto-creates task/review/PLAN.review.md
     (needs analysis approved). Sign off PLAN.review.md — that's the ONLY hard gate. Per-task
     reviews (task/review/T0n.review.md) are optional and created on demand, only to send a task back.
  5. /pw-execute --project $slug        → orchestrates worktree executors; stops at committed + verified.
  6. /pw-ship --project $slug           → pushes branches + opens MRs (the explicit publish step).
  7. /pw-close --project $slug          → tears down worktrees (safely), seeds learnings, Status=done.
  Check progress any time with /pw-status --project $slug.

  Optional side-loops, run whenever — never gate the numbered steps above:
    /pw-sync --project $slug   keep an open MR's branch fresh against a moved base.
    /pw-rfc --project $slug    publish approved analysis/plan content to an RFC doc (any platform, or none).

Full guide: $PW_HOME/README.md
EOF
