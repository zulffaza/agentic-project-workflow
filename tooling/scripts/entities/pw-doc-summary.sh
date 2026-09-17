#!/usr/bin/env bash
# ============================================================================
# pw-doc-summary.sh — auto-extract document summaries
#
#   pw-doc-summary.sh analysis <slug> <topic>   extract §1 problem + §4 chosen
#   pw-doc-summary.sh task <slug> <task-id>     extract Repo + Branch + goal
#   pw-doc-summary.sh plan <slug>               extract task count + SP + repos
#   pw-doc-summary.sh project <slug>            extract One-liner + phase + tasks
#
# Produces structured, machine-readable summaries from docs. Avoids agent
# reading whole docs just to extract one line.
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
# -h/--help before positional parsing: without this, "-h" would be taken as a slug/arg.
case "${1:-}" in -h|--help) pw_usage ;; esac

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"

die() { echo "pw-doc-summary: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scripts/toolchain/scaffold.sh $1)"; printf '%s' "$d"; }

[ $# -ge 2 ] || die "usage: pw-doc-summary.sh <type> <slug> [args...]"

TYPE="$1"
SLUG="$2"
shift 2

D="$(proj_dir "$SLUG")"

case "$TYPE" in
  analysis)
    [ $# -ge 1 ] || die "usage: pw-doc-summary.sh analysis <slug> <topic>"
    TOPIC="$1"
    f="$D/analysis/$TOPIC.md"
    [ -f "$f" ] || die "analysis doc not found: $f — /pw-analyze produces analysis docs (ls $D/analysis)"
    
    # Extract §1 problem (first paragraph after §1 heading)
    PROBLEM="$(awk '/^#{1,6}[ \t]+1\./{p=1; next} /^#{1,2}[ \t]/{p=0} p && /^$/{if(got_para) exit; next} p{got_para=1; print; exit}' "$f")"
    [ -n "$PROBLEM" ] || PROBLEM="(summary unavailable — read the doc)"
    echo "Problem: $PROBLEM"
    
    # Extract §4 chosen approach
    CHOSEN="$(grep '^\*\*Chosen approach:\*\*' "$f" | sed 's/^\*\*Chosen approach:\*\* *//' || echo "")"
    [ -n "$CHOSEN" ] || CHOSEN="(not yet chosen)"
    echo "Chosen approach: $CHOSEN"
    
    # Extract affected repos
    REPOS="$(awk '/^#{1,6}[ \t]+3\./{p=1; next} /^#{1,2}[ \t]/{p=0} p && /^- /{gsub(/^- `?/, ""); gsub(/`?.*/, ""); print}' "$f" | tr '\n' ',' | sed 's/,$//')"
    [ -n "$REPOS" ] || REPOS="(none listed)"
    echo "Affected repos: $REPOS"
    ;;
    
  task)
    [ $# -ge 1 ] || die "usage: pw-doc-summary.sh task <slug> <task-id>"
    TASK_ID="$1"
    f="$D/task/$TASK_ID.md"
    [ -f "$f" ] || die "task file not found: $f — check the task id against $D/task/T*.md"
    
    REPO="$(pw_field "$f" Repo)"
    echo "Repo: ${REPO:-(not set)}"
    
    BRANCH="$(pw_field "$f" Branch)"; BRANCH="${BRANCH//\`/}"; BRANCH="${BRANCH%% *}"
    echo "Branch: ${BRANCH:-(not set)}"
    
    # Goal: current template has a ## Goal section; legacy tasks carry it in step 1
    GOAL="$(awk '/^## Goal/{p=1; next} /^#/{p=0} p && NF {print; exit}' "$f")"
    [ -n "$GOAL" ] || GOAL="$(awk '/^## Steps/{p=1; next} /^#/{p=0} p && /^[0-9]+\./{gsub(/^[0-9]+\. */, ""); print; exit}' "$f")"
    [ -n "$GOAL" ] || GOAL="(no steps defined)"
    echo "Goal: $GOAL"
    
    SP="$(pw_field "$f" 'Story points')"
    echo "SP: ${SP:-?}"
    ;;
    
  plan)
    f="$D/task/PLAN.md"
    [ -f "$f" ] || die "PLAN.md not found: $f — run /pw-breakdown first"
    
    # Count tasks
    TASK_COUNT="$(awk '/^## Task( |s)/{p=1; next} p && /^\|.*T[0-9]/{count++} END{print count+0}' "$f")"
    
    # Sum SP
    TOTAL_SP="$(awk '/^## Task( |s)/{p=1; next} p && /^\|.*T[0-9]/{split($0,a,"|"); for(i in a){gsub(/ /,"",a[i]); if(a[i] ~ /^[0-9]+$/){sum+=a[i]}}} END{print sum+0}' "$f")"
    
    # Extract repos
    REPOS="$(awk -F'|' '/^## Repo( manifest|s in scope)/{p=1; next} /^## /{p=0} p && /^[ \t]*\|/ && !(/^[ \t]*\|[ \t:|-]+\|[ \t]*$/) { v = $2; gsub(/[ \t`*]/, "", v); if (v != "" && tolower(v) != "repo") print v }' "$f" | paste -sd, -)"
    [ -n "$REPOS" ] || REPOS="(none listed)"
    
    # Extract produced by
    PRODUCED_BY="$(pw_field "$f" 'Produced by')"; PRODUCED_BY="${PRODUCED_BY//\`/}"
    PRODUCED_BY="${PRODUCED_BY%%—*}"
    [ -n "$PRODUCED_BY" ] || PRODUCED_BY="(not set)"
    
    echo "Tasks: $TASK_COUNT (ΣSP=$TOTAL_SP)"
    echo "Repos: $REPOS"
    echo "Produced by: $PRODUCED_BY"
    ;;
    
  project)
    f="$D/README.md"
    [ -f "$f" ] || die "README.md not found: $f"
    
    # Extract One-liner
    ONELINER="$(grep '^- \*\*One-liner:\*\*' "$f" | sed 's/^- \*\*One-liner:\*\* *//' || echo "(not set)")"
    echo "One-liner: $ONELINER"
    
    # Extract phase
    PHASE="$("$HERE/../../pw-lib.sh" phase "$SLUG")"
    echo "Phase: $PHASE"
    
    # Count tasks by status
    TODO="$(awk '/^## Task( |s)/{p=1; next} /^## /{p=0} p && /\|.*todo.*\|/{count++} END{print count+0}' "$f")"
    IN_PROGRESS="$(awk '/^## Task( |s)/{p=1; next} /^## /{p=0} p && /\|.*in-progress.*\|/{count++} END{print count+0}' "$f")"
    DONE="$(awk '/^## Task( |s)/{p=1; next} /^## /{p=0} p && /\|.*done.*\|/{count++} END{print count+0}' "$f")"
    ACCEPTED="$(awk '/^## Task( |s)/{p=1; next} /^## /{p=0} p && /\|.*accepted.*\|/{count++} END{print count+0}' "$f")"
    
    echo "Tasks: $TODO todo, $IN_PROGRESS in-progress, $DONE done, $ACCEPTED accepted"
    ;;
    
  *)
    die "unknown type: $TYPE (expected: analysis|task|plan|project)"
    ;;
esac
