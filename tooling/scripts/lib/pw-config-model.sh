# shellcheck shell=bash
# ============================================================================
# pw-config-model.sh — provider-by-role cells, execution suggestions/routes, and
# markdown table storage shared by pw-config.sh, scaffold.sh, preflight, session.
#
# Storage contracts (project README, schema 2):
#   - **Configuration schema:** 2
#   ## Project configuration
#   ### Role models              | Provider | Role | Target model | Variant | Reasoning | Effort |
#   ### Execution suggestions   | Current provider | Execution provider | Target model | Target subagent | Variant | Reasoning | Effort | Thinking |
#
# Task files (schema 2) carry `## Execution routes` with the same columns as
# execution suggestions. The legacy scalar `Execute with:` field stays as a
# derived one-route summary for older readers.
#
# Global initialization cells (pw.config.sh, managed block):
#   PW_PROJECT_ROLE_<PROVIDER>_<ROLE>_{MODEL,VARIANT,REASONING,EFFORT}
#   PW_PROJECT_EXECUTION_SUGGESTION_<CURRENT>_{PROVIDER,MODEL,SUBAGENT,VARIANT,REASONING,EFFORT,THINKING}
#
# The library never writes files by itself: writers live in pw-config.sh and own
# locks, staging, logging, and recovery. This file only resolves and formats.
# ============================================================================

PW_ROLE_MODEL_HEADER='Provider|Role|Target model|Variant|Reasoning|Effort'
PW_EXECUTION_HEADER='Current provider|Execution provider|Target model|Target subagent|Variant|Reasoning|Effort|Thinking'
PW_CONFIG_SCHEMA_CURRENT=2

pw_role_names() { printf '%s\n' researcher analyst writer-task reviewer verifier ship-comment-analyst explorer; }

pw_role_valid() {
  case "${1:-}" in
    researcher|analyst|writer-task|reviewer|verifier|ship-comment-analyst|explorer) return 0 ;;
    *) return 1 ;;
  esac
}

pw_cfg_tok() { printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_' | tr -cd 'A-Z0-9_'; }
pw_cfg_tok_ok() { case "${1:-}" in ''|*[!A-Za-z0-9_-]*) return 1 ;; *) return 0 ;; esac; }
pw_cfg_lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

pw_provider_enabled() { # <provider>
  local p
  for p in ${PW_PROVIDERS[@]+"${PW_PROVIDERS[@]}"}; do
    [ "$p" = "$1" ] && return 0
  done
  return 1
}

# --- schema ------------------------------------------------------------------
pw_project_schema() { # <project-dir> -> 1 | 2 | 3 (unknown)
  local readme="$1/README.md" raw
  [ -f "$readme" ] || { printf '1'; return 0; }
  raw="$(grep -m1 '^- \*\*Configuration schema:\*\*' "$readme" 2>/dev/null | sed 's/^- \*\*Configuration schema:\*\*[[:space:]]*//' || true)"
  raw="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$raw" in
    ''|1) printf '1' ;;
    2)    printf '2' ;;
    *)    printf '3' ;;
  esac
}

pw_task_schema() { # <task-file>
  [ -f "$1" ] || { printf '1'; return 0; }
  if grep -qE '^##[[:space:]]+Execution routes[[:space:]]*$' "$1"; then printf '2'; else printf '1'; fi
}

# --- markdown table helpers --------------------------------------------------
# Values may not contain '|', TAB, newline, or backslash. `—` is an empty cell.
pw_tbl_value_ok() { # <value>
  case "$1" in *'|'*|*$'\t'*|*$'\n'*|*'\\'*) return 1 ;; esac
  return 0
}

pw_tbl_rows() { # <file> <heading> -> TAB-joined data rows
  local f="$1" heading="$2"
  [ -f "$f" ] || return 0
  awk -v h="$heading" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    $0 ~ "^##+[ \t]+" h "[ \t]*$" { inside=1; next }
    inside && $0 ~ /^##+[ \t]/ { exit }
    inside && incomment { if ($0 ~ /-->/) incomment=0; next }
    inside && $0 ~ /<!--/ { if ($0 !~ /-->/) incomment=1; next }
    inside && $0 ~ /^\|/ {
      n=split($0, c, "|")
      if (n < 2) next
      if (c[2] ~ /^[ \t]*:?-+:?[ \t]*$/) next
      if (trim(c[2]) == "Provider" || trim(c[2]) == "Current provider") next
      out=""
      for (i=2; i<n; i++) out = out (i>2 ? "\t" : "") trim(c[i])
      print out
    }' "$f"
}

pw_tbl_get() { # <file> <heading> <key-column> <key> -> row TAB-joined
  local f="$1" h="$2" col="$3" key="$4" row got
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    got="$(printf '%s' "$row" | cut -f"$col")"
    [ "$got" = "$key" ] || continue
    printf '%s' "$row"; return 0
  done <<EOF
$(pw_tbl_rows "$f" "$h")
EOF
  return 1
}

pw_tbl_col() { printf '%s' "$1" | cut -f"$2"; }

# Replace a row by key, or append it after the last table row. Creates the
# heading + header + separator when missing. <src> is read, <dst> written.
pw_tbl_set() { # <src> <dst> <heading> <header> <key-col> <key> <v1>…<vn>
  local src="$1" dst="$2" h="$3" header="$4" kcol="$5" key="$6"; shift 6
  local nvals=$# rendered="" hdr="" sep="" cell
  local -a values=("$@") heads=()
  IFS='|' read -r -a heads <<< "$header"
  for cell in "${heads[@]}"; do
    cell="$(printf '%s' "$cell" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    hdr="$hdr $cell |"; sep="$sep---|"
  done
  hdr="|${hdr}"; sep="|${sep}"
  for cell in "${values[@]}"; do rendered="$rendered $cell |"; done
  rendered="|${rendered}"
  awk -v h="$h" -v hdr="$hdr" -v sep="$sep" -v kcol="$kcol" -v key="$key" -v rendered="$rendered" '
    { lines[NR]=$0 }
    END {
      hin=0; for (r=1;r<=NR;r++) if (lines[r] ~ "^##+[ \t]+" h "[ \t]*$") { hin=r; break }
      if (!hin) {
        pin=0; for (r=1;r<=NR;r++) if (lines[r] ~ /^##+[ \t]+Project configuration[ \t]*$/) { pin=r; break }
        for (r=1;r<=NR;r++) {
          print lines[r]
          if (r==pin) { print ""; print "### " h; print hdr; print sep; print rendered }
        }
        if (!pin) { print ""; print "### " h; print hdr; print sep; print rendered }
        exit
      }
      t0=0; for (r=hin+1;r<=NR;r++) { if (lines[r] ~ /^##+[ \t]/) break; if (lines[r] ~ /^\|/) { t0=r; break } }
      last=0; found=0
      if (t0) {
        for (r=t0;r<=NR;r++) { if (lines[r] !~ /^\|/) break; last=r }
        ic=0
        for (r=t0+2;r<=last;r++) {
          if (ic) { if (lines[r] ~ /-->/) ic=0; continue }
          if (lines[r] ~ /<!--/) { if (lines[r] !~ /-->/) ic=1; continue }
          k=split(lines[r], c, "|")
          if (k < kcol+1) continue
          cell=c[kcol+1]; gsub(/^[ \t]+|[ \t]+$/, "", cell)
          if (cell == key) { lines[r]=rendered; found=1; break }
        }
      }
      if (!found && last) {
        for (r=1;r<=NR;r++) { print lines[r]; if (r==last) print rendered }
        exit
      }
      if (!found) {
        for (r=1;r<=NR;r++) { print lines[r]; if (r==hin) { print ""; print hdr; print sep; print rendered } }
        exit
      }
      for (r=1;r<=NR;r++) print lines[r]
    }' "$src" > "$dst"
}

pw_tbl_del() { # <src> <dst> <heading> <key-col> <key>
  local src="$1" dst="$2" h="$3" kcol="$4" key="$5"
  awk -v h="$h" -v kcol="$kcol" -v key="$key" '
    { lines[NR]=$0 }
    END {
      hin=0; for (r=1;r<=NR;r++) if (lines[r] ~ "^##+[ \t]+" h "[ \t]*$") { hin=r; break }
      if (!hin) { for (r=1;r<=NR;r++) print lines[r]; exit }
      ic=0
      for (r=1;r<=NR;r++) {
        if (r<=hin) { print lines[r]; continue }
        if (ic) { if (lines[r] ~ /-->/) ic=0; print lines[r]; continue }
        if (lines[r] ~ /<!--/) { if (lines[r] !~ /-->/) ic=1; print lines[r]; continue }
        if (lines[r] ~ /^##+[ \t]/ || lines[r] !~ /^\|/) { print lines[r]; continue }
        k=split(lines[r], c, "|")
        if (k >= kcol+1) { cell=c[kcol+1]; gsub(/^[ \t]+|[ \t]+$/, "", cell); if (cell == key) continue }
        print lines[r]
      }
    }' "$src" > "$dst"
}


pw_tbl_get2() { # <file> <heading> <col1> <key1> <col2> <key2> -> row
  local f="$1" h="$2" c1="$3" k1="$4" c2="$5" k2="$6" row a b
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    a="$(printf '%s' "$row" | cut -f"$c1")"
    b="$(printf '%s' "$row" | cut -f"$c2")"
    [ "$a" = "$k1" ] && [ "$b" = "$k2" ] || continue
    printf '%s' "$row"; return 0
  done <<EOF
$(pw_tbl_rows "$f" "$h")
EOF
  return 1
}

pw_tbl_set2() { # <src> <dst> <heading> <header> <col1> <key1> <col2> <key2> <v1>…<vn>
  local src="$1" dst="$2" h="$3" header="$4" k1c="$5" k1="$6" k2c="$7" k2="$8"; shift 8
  local nvals=$# rendered="" hdr="" sep="" cell
  local -a values=("$@") heads=()
  IFS='|' read -r -a heads <<< "$header"
  for cell in "${heads[@]}"; do
    cell="$(printf '%s' "$cell" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    hdr="$hdr $cell |"; sep="$sep---|"
  done
  hdr="|${hdr}"; sep="|${sep}"
  for cell in "${values[@]}"; do rendered="$rendered $cell |"; done
  rendered="|${rendered}"
  awk -v h="$h" -v hdr="$hdr" -v sep="$sep" -v k1c="$k1c" -v k1="$k1" -v k2c="$k2c" -v k2="$k2" -v rendered="$rendered" '
    { lines[NR]=$0 }
    END {
      hin=0; for (r=1;r<=NR;r++) if (lines[r] ~ "^##+[ \t]+" h "[ \t]*$") { hin=r; break }
      if (!hin) {
        pin=0; for (r=1;r<=NR;r++) if (lines[r] ~ /^##+[ \t]+Project configuration[ \t]*$/) { pin=r; break }
        for (r=1;r<=NR;r++) { print lines[r]; if (r==pin) { print ""; print "### " h; print hdr; print sep; print rendered } }
        if (!pin) { print ""; print "### " h; print hdr; print sep; print rendered }
        exit
      }
      t0=0; for (r=hin+1;r<=NR;r++) { if (lines[r] ~ /^##+[ \t]/) break; if (lines[r] ~ /^\|/) { t0=r; break } }
      last=0; found=0
      if (t0) {
        for (r=t0;r<=NR;r++) { if (lines[r] !~ /^\|/) break; last=r }
        ic=0
        for (r=t0+2;r<=last;r++) {
          if (ic) { if (lines[r] ~ /-->/) ic=0; continue }
          if (lines[r] ~ /<!--/) { if (lines[r] !~ /-->/) ic=1; continue }
          n=split(lines[r], c, "|")
          if (n < k2c+1) continue
          a=c[k1c+1]; gsub(/^[ \t]+|[ \t]+$/, "", a)
          b=c[k2c+1]; gsub(/^[ \t]+|[ \t]+$/, "", b)
          if (a == k1 && b == k2) { lines[r]=rendered; found=1; break }
        }
      }
      if (!found && last) {
        for (r=1;r<=NR;r++) { print lines[r]; if (r==last) print rendered }
        exit
      }
      if (!found) {
        for (r=1;r<=NR;r++) { print lines[r]; if (r==hin) { print ""; print hdr; print sep; print rendered } }
        exit
      }
      for (r=1;r<=NR;r++) print lines[r]
    }' "$src" > "$dst"
}

# --- role cells --------------------------------------------------------------
pw_role_cell_var() { # <provider> <role> <FIELD>
  printf 'PW_PROJECT_ROLE_%s_%s_%s' "$(pw_cfg_tok "$1")" "$(pw_cfg_tok "$2")" "$3"
}

# Fills PW_CELL_MODEL/VARIANT/REASONING/EFFORT. Returns 0 when MODEL is set.
pw_global_role_cell() { # <provider> <role>
  local p r f var
  p="$(pw_cfg_lc "$1")"; r="$2"
  pw_cfg_tok_ok "$p" || return 1
  pw_role_valid "$r" || return 1
  for f in MODEL VARIANT REASONING EFFORT; do
    var="$(pw_role_cell_var "$p" "$r" "$f")"
    if declare -p "$var" >/dev/null 2>&1; then printf -v "PW_CELL_$f" '%s' "${!var}"; else printf -v "PW_CELL_$f" '%s' ""; fi
  done
  [ -n "${PW_CELL_MODEL:-}" ]
}

pw_global_suggestion_var() { # <current-provider> <FIELD>
  printf 'PW_PROJECT_EXECUTION_SUGGESTION_%s_%s' "$(pw_cfg_tok "$1")" "$2"
}

# Fills PW_SUG_PROVIDER/MODEL/SUBAGENT/VARIANT/REASONING/EFFORT/THINKING.
pw_global_suggestion() { # <current-provider>
  local c f var
  c="$(pw_cfg_lc "$1")"; pw_cfg_tok_ok "$c" || return 1
  for f in PROVIDER MODEL SUBAGENT VARIANT REASONING EFFORT THINKING; do
    var="$(pw_global_suggestion_var "$c" "$f")"
    if declare -p "$var" >/dev/null 2>&1; then printf -v "PW_SUG_$f" '%s' "${!var}"; else printf -v "PW_SUG_$f" '%s' ""; fi
  done
  [ -n "${PW_SUG_MODEL:-}" ]
}

# Prints "<model>\t<variant>\t<reasoning>\t<effort>"; non-zero when absent.
pw_project_role_row() { # <project-dir> <provider> <role>
  local row
  row="$(pw_tbl_get2 "$1/README.md" "Role models" 1 "$(pw_cfg_lc "$2")" 2 "$3" 2>/dev/null || true)"
  [ -n "$row" ] || return 1
  printf '%s\t%s\t%s\t%s\n' "$(pw_tbl_col "$row" 3)" "$(pw_tbl_col "$row" 4)" "$(pw_tbl_col "$row" 5)" "$(pw_tbl_col "$row" 6)"
}

pw_project_suggestion_row() { # <project-dir> <current-provider>
  pw_tbl_get "$1/README.md" "Execution suggestions" 1 "$(pw_cfg_lc "$2")" 2>/dev/null
}

# --- task execution routes ---------------------------------------------------
# Prints "<execution-provider>\t<model>\t<subagent>\t<variant>\t<reasoning>\t<effort>\t<thinking>".
pw_task_route_row() { # <task-file> <current-provider>
  local row
  row="$(pw_tbl_get "$1" "Execution routes" 1 "$(pw_cfg_lc "$2")" 2>/dev/null || true)"
  [ -n "$row" ] || return 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(pw_tbl_col "$row" 2)" "$(pw_tbl_col "$row" 3)" "$(pw_tbl_col "$row" 4)" \
    "$(pw_tbl_col "$row" 5)" "$(pw_tbl_col "$row" 6)" "$(pw_tbl_col "$row" 7)" "$(pw_tbl_col "$row" 8)"
}

pw_task_route_keys() { # <task-file>
  [ -f "$1" ] || return 0
  pw_tbl_rows "$1" "Execution routes" 2>/dev/null | cut -f1 | awk 'NF' || true
}

# One axis out of the stored `variant:x,reasoning:y,effort:z` token (empty when absent).
_tuning_field() { # <token> <variant|reasoning|effort>
  local kv
  for kv in $(printf '%s' "${1:-}" | tr ',' ' '); do
    [ "${kv%%:*}" = "$2" ] && { printf '%s' "${kv#*:}"; return 0; }
  done
  return 0
}

pw_cell_empty() { case "${1:-}" in ''|'—'|'-') return 0 ;; *) return 1 ;; esac; }
pw_cell_or_dash() { if pw_cell_empty "${1:-}"; then printf '—'; else printf '%s' "$1"; fi; }

# Validate optional tuning against the local capability table. Prints nothing on
# success; writes the reason on stderr and returns 1 otherwise.
pw_role_tuning_check() { # <provider> <variant> <reasoning> <effort>
  local p="$1" v="$2" r="$3" e="$4" conf=""
  [ -n "$v$r$e" ] || return 0
  case "$p" in
    kilo)   [ -z "$r$e" ] || { echo "kilo supports variant only (got reasoning/effort)" >&2; return 1; } ;;
    claude) [ -z "$v$r" ] || { echo "claude supports effort only (got variant/reasoning)" >&2; return 1; } ;;
    cursor|codex|opencode) ;;
    *) echo "provider '$p' has no verified tuning mapping" >&2; return 1 ;;
  esac
  conf="$(pw_model_capability "$p" variant 2>/dev/null || true)"
  case "$conf" in
    unsupported) [ -z "$v" ] || { echo "$p does not support variant" >&2; return 1; } ;;
    unknown) : ;;
    *) [ -z "$v" ] || pw_model_is_one_of "$v" "$conf" || { echo "variant '$v' is not listed for $p" >&2; return 1; } ;;
  esac
  conf="$(pw_model_capability "$p" reasoning 2>/dev/null || true)"
  case "$conf" in
    unsupported) [ -z "$r" ] || { echo "$p does not support reasoning" >&2; return 1; } ;;
    unknown) : ;;
    *) [ -z "$r" ] || pw_model_is_one_of "$r" "$conf" || { echo "reasoning '$r' is not listed for $p" >&2; return 1; } ;;
  esac
  conf="$(pw_model_capability "$p" effort 2>/dev/null || true)"
  case "$conf" in
    unsupported) [ -z "$e" ] || { echo "$p does not support effort" >&2; return 1; } ;;
    unknown) : ;;
    *) [ -z "$e" ] || pw_model_is_one_of "$e" "$conf" || { echo "effort '$e' is not listed for $p" >&2; return 1; } ;;
  esac
  return 0
}

# --- proposals ---------------------------------------------------------------
# Proposal = directory with `meta` (key=value) and `changes` (TSV:
# key, owner, old, new, action). Runtime state only; preview creates no project
# artifacts.
pw_proposal_dir() { printf '%s' "${PW_PROPOSAL_DIR:-${PW_STATE_DIR:-$HOME/.local/state/pw}/proposals}"; }
pw_proposal_path() { printf '%s/%s' "$(pw_proposal_dir)" "$1"; }
pw_proposal_exists() { [ -f "$(pw_proposal_path "$1")/meta" ] && [ -f "$(pw_proposal_path "$1")/changes" ]; }

pw_proposal_create() { # <kind> <scope-label> <changes-file> -> id
  local kind="$1" scope="$2" changes="$3" id dir
  id="${kind}-$(date +%s)-$$-$RANDOM"
  dir="$(pw_proposal_path "$id")"
  mkdir -p "$dir" || return 1
  cp "$changes" "$dir/changes" || return 1
  {
    printf 'kind=%s\n' "$kind"
    printf 'scope=%s\n' "$scope"
    printf 'created=%s\n' "$(date +%s)"
  } > "$dir/meta"
  # A revision supersedes earlier unapplied previews of the same kind and scope.
  local old odir ostate
  for old in "$(pw_proposal_dir)"/*; do
    [ -d "$old" ] || continue
    [ "$(basename "$old")" = "$id" ] && continue
    [ "$(pw_proposal_field "$(basename "$old")" kind 2>/dev/null || true)" = "$kind" ] || continue
    [ "$(pw_proposal_field "$(basename "$old")" scope 2>/dev/null || true)" = "$scope" ] || continue
    ostate="$(pw_proposal_field "$(basename "$old")" state 2>/dev/null || true)"
    [ -z "$ostate" ] || continue
    pw_proposal_mark "$(basename "$old")" state superseded
  done
  printf '%s' "$id"
}

pw_proposal_field() { sed -n "s/^$2=//p" "$(pw_proposal_path "$1")/meta" 2>/dev/null | head -1; }
pw_proposal_mark() { printf '%s=%s\n' "$2" "$3" >> "$(pw_proposal_path "$1")/meta"; }
