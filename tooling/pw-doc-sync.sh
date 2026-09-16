#!/usr/bin/env bash
# ============================================================================
# pw-doc-sync.sh — reconcile all documents from on-disk state
#
#   pw-doc-sync.sh <slug> [--dashboard-only | --plan-only | --tasks-only]
#
# Reconciles document relationships:
# - Dashboard sync (README.md): task status table, MR table
# - PLAN sync (task/PLAN.md): header metadata, task table
# - Task file sync: ## Result fields reflect actual git state
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"

REPOS_DIR="${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}"

die() { echo "pw-doc-sync: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scaffold.sh $1)"; printf '%s' "$d"; }

SYNC_MODE="all"
for arg in "$@"; do
  case "$arg" in
    --dashboard-only) SYNC_MODE="dashboard" ;;
    --plan-only) SYNC_MODE="plan" ;;
    --tasks-only) SYNC_MODE="tasks" ;;
    -h|--help) pw_usage ;;
    -*) die "unknown option: $arg" ;;
  esac
done

# Extract slug (first non-flag argument)
SLUG=""
for arg in "$@"; do
  [[ "$arg" =~ ^-- ]] && continue
  SLUG="$arg"
  break
done

[ -n "$SLUG" ] || die "usage: pw-doc-sync.sh <slug> [--dashboard-only | --plan-only | --tasks-only]"

D="$(proj_dir "$SLUG")"
README="$D/README.md"
PLAN="$D/task/PLAN.md"

[ -f "$README" ] || die "README.md not found"

sync_dashboard() {
  echo "Syncing dashboard (README.md)..."
  [ -f "$PLAN" ] || { echo "PLAN.md not found, skipping"; return 0; }
  
  local WORK; WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' RETURN
  
  # ---- ground truth per task (from the task file; PLAN status is the tie-break) ----
  local plan_st="$WORK/plan-status" TASKROWS="$WORK/task-rows" MRROWS="$WORK/mr-rows"
  pw_plan_pairs "$PLAN" | tr '|' '\t' > "$plan_st"
  : > "$TASKROWS"; : > "$MRROWS"
  local tf id st repo branch base title line mr
  for tf in "$D/task"/T*.md; do
    [ -f "$tf" ] || continue
    id="$(basename "$tf" .md)"; [[ "$id" =~ ^T[0-9]+ ]] || continue
    st="$(pw_field "$tf" Status)"; [ -n "$st" ] || st="$(awk -F'\t' -v i="$id" '$1==i{print $2; exit}' "$plan_st")"; st="${st:-todo}"
    repo="$(pw_field "$tf" Repo)"; repo="${repo//\`/}"
    branch="$(pw_field "$tf" Branch)"; branch="${branch//\`/}"; branch="${branch%% *}"
    base="$(pw_field "$tf" 'Base branch')"; base="${base//\`/}"; base="${base%% *}"; [ -n "$base" ] || base="—"
    title="$(grep '^# ' "$tf" | head -1 | sed 's/^# //; s/^T[0-9]*[: ]*//' | pw_trim)"; [ -n "$title" ] || title="—"
    mr="$(pw_task_mr_url "$tf")"  # Result-scoped: **MR:** field -> its URL/sentinel, else bare URL
    [ "$mr" = "(none)" ] && mr="—"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$st" "$repo" "$branch" "$base" "$title" "$mr" >> "$TASKROWS"
  done
  
  # ---- table rebuilder: keeps the existing header+separator, regenerates data rows;
  #      cells we can derive are taken from TASKROWS, everything else (Notes/State/Build/…)
  #      is preserved per-task-id from the old rows; unknown-to-either cells get —.
  _rebuild_table() {
    local hre="$1" bounds hdrno dstart dend HDR CELLS n i name line id v
    bounds="$(awk -v hre="$hre" '
      BEGIN { want=0; state=0 }
      /^## / { if (!want && $0 ~ hre) { want=1; sec=NR; next } else if (want && state>=1) { print sec, hdr, (dstartNR ? dstartNR : hdr+2), NR-1; exit } else if (want && state==0) { want=0 } }
      want && state==0 && /^[ \t]*\|/ { hdr=NR; state=1; next }
      want && state==1 { # separator expected on hdr+1; data after
        if (NR <= hdr+1) { dstartNR = NR+1 }
        if ($0 !~ /^[ \t]*\|/ && $0 !~ /^[ \t]*$/) { if (!dendFound) { print sec, hdr, dstartNR, NR-1; dendFound=1 } }
      }
      END { if (want && state==1 && !dendFound) print sec, hdr, (dstartNR ? dstartNR : hdr+2), NR }' "$README")"
    [ -n "$bounds" ] || { echo "  (no table under /$hre/ — left untouched)"; return 0; }
    set -- $bounds; hdrno="$2"; dstart="$3"; dend="$4"
    HDR="$(sed -n "${hdrno}p" "$README")"
    
    # header cell names (lowercased, non-code stripped); positional fields after IFS split on |
    CELLS="$(printf '%s' "$HDR" | awk -F'|' '{ for (i = 2; i < NF; i++) { v = $i; gsub(/[ \t`*]/, "", v); print tolower(v) } }')"
    
    # preserved values from existing data rows: "<id>\t<name>\t<value>"
    local PRES="$WORK/pres.${hre//[^A-Za-z]/}"
    : > "$PRES"
    if [ "$dend" -ge "$dstart" ]; then
      printf '%s\n' "$CELLS" > "$WORK/names"
      sed -n "${dstart},${dend}p" "$README" | awk -F'|' -v namesf="$WORK/names" '
        BEGIN { n = 0; while ((getline x < namesf) > 0) NAME[++n] = x }
        { id = $2; gsub(/[ \t]/, "", id); if (id !~ /^T[0-9]+/) next
          for (i = 0; i < n; i++) { v = $(i + 2); gsub(/^[ \t]+/, "", v); gsub(/[ \t|]+$/, "", v); print id "\t" NAME[i + 1] "\t" v } }' > "$PRES"
    fi
    
    # emit new data rows
    local OUT="$WORK/newrows.${hre//[^A-Za-z]/}"
    : > "$OUT"
    while IFS=$'\t' read -r id st repo branch base title mr; do
      local row ln col val
      row=""
      while IFS= read -r col; do
        case "$col" in
          id|task) val="$id" ;;
          status) val="$st" ;;
          repo) val="$repo" ;;
          branch) val="$branch" ;;
          title) val="$title" ;;
          mr) val="$mr" ;;
          "target branch"|"target"|"base branch") val="$base" ;;
          *) val="$(awk -F'\t' -v i="$id" -v c="$col" '$1==i && $2==c { found=1; print $3 } END { if (!found) print "" }' "$PRES")"
             [ -n "$val" ] || val="—" ;;
        esac
        row="$row| $val "
      done <<< "$CELLS"
      echo "${row}|" >> "$OUT"
    done < "$TASKROWS"
    
    # splice: [1..dstart-1] + newrows + [dend+1..]
    local TMP="$WORK/README"
    { sed -n "1,$((dstart-1))p" "$README"; cat "$OUT"; sed -n "$((dend+1)),\$p" "$README"; } > "$TMP"
    mv "$TMP" "$README"
  }
  
  _rebuild_table '^## Task( status|s| table)' 
  
  
  # ---- MR table: append-only rows for tasks with a Result MR (preserves State/Build) ----
  while IFS=$'\t' read -r id st repo branch base title mr; do
    [ "$mr" != "—" ] && [ -n "$mr" ] || continue
    if ! grep -qE "^\|[ \t]*$id[ \t]*\|" "$README"; then
      local mline hdr_cells c col row val
      mline=""
      hdr_cells="$(awk -F'|' '/^## Merge requests/{p=1;next} p && /^## /{exit} p && /^[ \t]*\|/ && NF>2 { for (i=2;i<NF;i++){ v=$i; gsub(/[ \t`*]/,"",v); print tolower(v) } exit }' "$README")"
      row=""
      while IFS= read -r col; do
        case "$col" in
          task|id) val="$id" ;;
          repo) val="$repo" ;;
          mr) val="$mr" ;;
          "target branch") val="$base" ;;
          state) val="open" ;;
          build) val="—" ;;
          *) val="—" ;;
        esac
        row="$row| $val "
      done <<< "$hdr_cells"
      # insert after the separator row of the MR table
      awk -v ins="${row}|" '/^## Merge requests/{p=1} p && /^[ \t]*\|[-: |]+\|$/ { print; print INS; p=0; next } { print }' INS="${row}|" "$README" > "$WORK/re" && mv "$WORK/re" "$README"
    fi
  done < "$TASKROWS"
  
  # refresh State for MR rows from PRESERVED old values is automatic; URL changes:
  while IFS=$'\t' read -r id st repo branch base title mr; do
    [ "$mr" != "—" ] && [ -n "$mr" ] || continue
    grep -qE "^\|[ \t]*$id[ \t]*\|" "$README" || continue
    case "$mr" in *://*) awk -v url="$mr" '
        /^## Merge requests/{ p=1; print; next } p && /^## /{ p=0; print; next }
        p && /^[ \t]*\|[ \t]*'"$id"'[ \t]*\|/ {
          n = split($0, c, "|")
          for (i = 2; i < n; i++) { h = c[i]; gsub(/[ \t`*]/, "", h); if (tolower(h) == "mr") c[i] = " " url " " }
          out = ""; for (i = 1; i <= n; i++) out = out c[i] (i < n ? "|" : ""); print out; next
        }
        { print }' "$README" > "$WORK/re" && mv "$WORK/re" "$README" ;; esac
  done < "$TASKROWS"
  
  echo "Dashboard sync complete"
}

sync_plan() {
  echo "Syncing PLAN.md..."
  
  [ -f "$PLAN" ] || { echo "PLAN.md not found, skipping"; return 0; }
  
  # Sync task count and SP totals
  TASK_COUNT="$(ls -1 "$D/task"/T*.md 2>/dev/null | wc -l | pw_trim)"
  TOTAL_SP=0
  for task_file in "$D/task"/T*.md; do
    [ -f "$task_file" ] || continue
    SP="$(pw_field "$task_file" 'Story points')"; SP="${SP%% *}"
    [[ "$SP" =~ ^[0-9]+$ ]] && TOTAL_SP=$((TOTAL_SP + SP))
  done
  
  # Update PLAN header if needed
  if grep -q '^\*\*Task count:\*\*' "$PLAN"; then
    awk -v count="$TASK_COUNT" -v sp="$TOTAL_SP" '
      /^\*\*Task count:\*\*/ { print "- **Task count:** " count " (ΣSP=" sp ")"; next }
      { print }
    ' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
  fi
  
  echo "PLAN sync complete"
}

sync_tasks() {
  echo "Syncing task files..."
  
  for task_file in "$D/task"/T*.md; do
    [ -f "$task_file" ] || continue
    task_id="$(basename "$task_file" .md)"
    
    REPO="$(pw_field "$task_file" Repo)"
    BRANCH="$(pw_field "$task_file" Branch)"; BRANCH="${BRANCH//\`/}"
    BASE="$(pw_field "$task_file" 'Base branch')"; BASE="${BASE//\`/}"; BASE="${BASE%% *}"; BASE="${BASE:-master}"
    
    [ -n "$REPO" ] && [ -n "$BRANCH" ] || continue
    
    REPO_DIR="$REPOS_DIR/$REPO"
    [ -d "$REPO_DIR" ] || continue
    
    # Check for commits
    COMMIT_COUNT=0
    if git -C "$REPO_DIR" rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
      COMMIT_COUNT="$(git -C "$REPO_DIR" log --oneline "origin/$BASE..origin/$BRANCH" 2>/dev/null | wc -l | pw_trim)"
    fi
    
    # Update Result section if needed
    if [ "$COMMIT_COUNT" -gt 0 ]; then
      if ! grep -q 'commits' "$task_file" 2>/dev/null; then
        # Append commit count to Result section
        if grep -q '^## Result' "$task_file"; then
          awk -v count="$COMMIT_COUNT" '/^## Result/{p=1; print; print "- " count " commit(s)"; next} p && /^## /{p=0} {print}' \
            "$task_file" > "$task_file.tmp" && mv "$task_file.tmp" "$task_file"
        fi
      fi
    fi
  done
  
  echo "Task file sync complete"
}

case "$SYNC_MODE" in
  dashboard) sync_dashboard ;;
  plan) sync_plan ;;
  tasks) sync_tasks ;;
  all)
    sync_dashboard
    sync_plan
    sync_tasks
    ;;
esac

echo "Document sync complete"
