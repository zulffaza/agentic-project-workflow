#!/usr/bin/env bash
# Scaffold a new agentic-workflow project from template/.
# Usage: tooling/scaffold.sh <project-slug>
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # tooling/
PW_HOME="$(cd "$HERE/.." && pwd)"                       # repo root (the bundle)
TEMPLATE_DIR="$PW_HOME/template"                        # what a project is made of

# Three roots for stamping {{PW_*}} tokens into copied templates (see gen-commands.sh).
PW_PROJECTS="${PW_PROJECTS:-$(cd "$PW_HOME/.." && pwd)}"
PW_REPOS="${PW_REPOS:-$(cd "$PW_PROJECTS/.." && pwd)}"

slug="${1:-}"
if [[ -z "$slug" ]]; then
  echo "Usage: $(basename "$0") <project-slug>   (e.g. spring-boot-3-upgrade)" >&2
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

# Copy the template tree (dashboard template is rendered separately, below).
mkdir -p "$dest"
rsync -a \
  --exclude '/PROJECT.template.md' \
  --exclude '.DS_Store' \
  "$TEMPLATE_DIR"/ "$dest"/

# Render the project dashboard as the project's README.md.
sed "s/<PROJECT_NAME>/$slug/g; s|<CREATED>|$(date '+%F %H:%M')|" \
  "$TEMPLATE_DIR/PROJECT.template.md" > "$dest/README.md"

# Stamp {{PW_*}} tokens (absolute paths) into every copied markdown file.
find "$dest" -type f -name '*.md' -print0 | while IFS= read -r -d '' md; do
  perl -pi -e "s{\Q{{PW_HOME}}\E}{$PW_HOME}g;
               s{\Q{{PW_PROJECTS}}\E}{$PW_PROJECTS}g;
               s{\Q{{PW_REPOS}}\E}{$PW_REPOS}g" "$md"
done

# Keep empty phase dirs present even if rsync left them out; add the review/ subdirs.
# (No per-project sub-agent/ dir — reusable agents are seeded from tooling/agents/ via bootstrap.)
mkdir -p "$dest/context" "$dest/analysis/review" "$dest/task/review" "$dest/worktree"

# Seed the append-only activity log.
cat > "$dest/LOG.md" <<LOGEOF
# Activity log — $slug

Append-only audit trail. One line per meaningful action: phase transitions, sub-agent spawns,
commits, pushes, MRs, review passes, close-out. Newest at the bottom. The /pw-* commands append
here automatically (via pw-lib.sh log — never hand-edit); add manual notes the same way, or as
another Markdown bullet, so it reads consistently in preview.

Format: a bullet per entry — "- **YYYY-MM-DD HH:MM** · \`<phase/actor>\` — <what happened>"

- **$(date "+%Y-%m-%d %H:%M")** · \`scaffold\` — project created
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
  3. /pw-analyze $slug        → writes analysis/ + auto-creates analysis/review/<topic>.review.md,
     sets Status=analysis. Add items to that review file, /pw-review $slug, sign off when satisfied.
  4. /pw-breakdown $slug      → writes task/PLAN.md + T0n.md + auto-creates task/review/PLAN.review.md
     (needs analysis approved). Sign off PLAN.review.md — that's the ONLY hard gate. Per-task
     reviews (task/review/T0n.review.md) are optional and created on demand, only to send a task back.
  5. /pw-execute $slug        → orchestrates worktree executors; stops at committed + verified.
  6. /pw-ship $slug           → pushes branches + opens MRs (the explicit publish step).
  7. /pw-close $slug          → tears down worktrees (safely), seeds learnings, Status=done.
  Check progress any time with /pw-status $slug.

  Optional side-loops, run whenever — never gate the numbered steps above:
    /pw-sync $slug   keep an open MR's branch fresh against a moved base.
    /pw-rfc $slug    publish approved analysis/plan content to an RFC doc (any platform, or none).

Full guide: $PW_HOME/README.md
EOF
