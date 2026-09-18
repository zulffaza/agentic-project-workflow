#!/usr/bin/env bash
# ============================================================================
# pw-help.sh — deterministic discovery: one help surface for commands + operators
#
#   pw-help.sh overview   [--json]
#       Global at-a-glance: one line per command AND one line per exposed
#       operator, grouped by phase bucket. Each operator line prints the
#       command-form invocation plus its use case (the first sentence of its
#       usage-header paragraph, or the command file's own definition line for
#       command-level sugar operators). Rendered live from command frontmatter
#       + script usage headers — zero maintained snapshot. Includes pw-help.
#
#   pw-help.sh command    <name> [<slug>] [--full|--json]
#       The how-to manual for one command: per-operator blocks (Use when / Does /
#       Shape / doctrine labels / runnable example line) lifted from the command
#       file's own bullets + the entity's usage-header paragraphs, the entity and
#       toolchain scripts with their S1b facet-grouped operator sigs, doc
#       pointers, and the frontmatter summary. With <slug> the invocation slots
#       show that slug. --full renders the entire command file (placeholders
#       substituted) for the rare reader that needs the doctrine verbatim.
#
#   pw-help.sh operators  <name> [<operator>]
#       Deepest level. The name slot resolves a command name, a bare name
#       (pw- prefix added), or an entity/toolchain script basename — library
#       scripts are never listable (they are source-only: L2). Without the
#       operator slot: the verbatim usage-header dump (S1b facet lines
#       included). With it: just that operator's usage-header paragraph,
#       one occurrence per owning script, facet-labelled.
#
#   pw-help.sh workflow   [--json]
#       The lifecycle spine: phases, their commands, and where the review
#       gates live — rendered from $PW_VALID_PHASES + the phase map, so the
#       command half can never drift.
#
#   pw-help.sh --selftest                  run the isolated harness case.
#
# Read-only by contract: help opens files for read and invokes an audited
# whitelist of read operators only (pw-status.sh phase; pw-review.sh
# gate/has-open/count/scan). It never runs a setter and never writes — a
# command line it prints is example text, never executed.
#
# Exit codes: 0 success · 2 usage / unknown name (stderr carries a → fix:
# hint, plus a did-you-mean when a command name is close). Names are always
# echoed in full canonical form (pw-review, never bare review); bare input
# normalizes mechanically.
# Portable bash 3.2+.
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
TOOL="$PW_HOME/tooling"
. "$HERE/../lib/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
CMDS="$TOOL/commands"

die() { echo "pw-help: $*" >&2; exit 2; }

# --- the phase -> command map (embedded knowledge; the static.sh set-equality
# canary pins its names against $CMDS, so a new command cannot stay invisible) ---
HELP_PHASE_MAP="setup|pw-new pw-adopt pw-context pw-doctor;analysis|pw-research pw-analyze pw-review;breakdown|pw-breakdown pw-rfc;executing|pw-execute pw-verify pw-sync;ship|pw-ship;close|pw-close;anytime|pw-status pw-help"

# --- shared helpers -------------------------------------------------------------
sub() { sed -e "s|{{PW_HOME}}|$PW_HOME|g" -e "s|{{PW_PROJECTS}}|$PW_PROJECTS|g"; }
jstr() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
TABS="$(printf '\t')"
BT="$(printf '\140')"    # literal backtick — kept OUT of double quotes (there it starts command-sub)
TF="$(printf '\047')"    # literal single quote, same reason

# fmof <file> <key> — frontmatter value (same parse as gen-commands).
fmof() {
  awk -v k="$2" '
    NR==1 && $0=="---" {infm=1; next}
    infm && $0=="---" {exit}
    infm { if ($0 ~ "^"k":") { sub("^"k":[ \t]*",""); print; exit } }
  ' "$1" | sed -e "s/^[\"']//" -e "s/[\"']$//"
}

# hdr_lines <script> — usage-header block (between the "# ====" rules), decommented
# with leading spaces stripped so operator signatures anchor at column 1.
hdr_lines() {
  awk '/^# =+$/{c++; next} c==1 {if (/^#/) {sub(/^# ?/,""); print}} c>=2{exit}' "$1"
}

# ops_of <script> — operator names from "pw-<s>.sh <op>  <args>" usage-header signatures.
ops_of() {
  hdr_lines "$1" | awk '/^  pw-[a-z0-9-]+\.sh +[a-z][a-z0-9-]*([ ]|$)/{print $2}'
}

# sig_of <script> <op> — argument string from the operator's usage-header signature.
sig_of() {
  hdr_lines "$1" | awk -v op="$2" '
    $0 ~ "^  pw-[a-z0-9-]+\\.sh +"op"([ ]|$)" { sub(/^  pw-[a-z0-9-]+\.sh +[a-z][a-z0-9-]*[ ]+/, ""); print; exit }'
}

# para_of <script> <op> — the operator\'s usage-header paragraph, joined to one line.
para_of() {
  hdr_lines "$1" | awk -v op="$2" '
    function tryflush() {
      if (buf=="") return
      if (txt != "" && index(SUBSEP buf SUBSEP, SUBSEP op SUBSEP)) { printf "%s\n", txt; found=1; exit }
    }
    /^  pw-[a-z0-9-]+\.sh +[a-z][a-z0-9-]*([ ]|$)/ {
      tryflush()
      if (txt != "") { buf=$2; txt="" } else buf = (buf=="" ? $2 : buf SUBSEP $2)
      next }
    NF==0 { if (txt!="" && buf!="") { tryflush(); buf=""; txt="" } next }
    { if (buf!="" && !found) { sub(/^[ ]+/,""); txt = (txt=="" ? $0 : txt " " $0) } }
    END { tryflush() }' | head -1
}

# gist <text> — first sentence; a period is a boundary only before space/EOL
# (so "INDEX.md\'s" and "pw-rfc-comments.sh)" survive).
gist() {
  printf '%s' "$1" | awk '{
    s=$0
    for (i=1; i<=length(s); i++)
      if (substr(s,i,1)=="." && (i==length(s) || substr(s,i+1,1)==" ")) { print substr(s,1,i-1); exit }
    print s
  }'
}

# facets_map <script> — "facet<TAB>op" lines from the S1b Facets block.
facets_map() {
  hdr_lines "$1" | awk '
    /WRITE[ ]*=|READ[ ]*=|SPECIAL[ ]*=/ {
      line=$0
      if (line ~ /WRITE[ ]*=/) { facet="write"; sub(/^.*WRITE[ ]*=/,"",line) }
      else if (line ~ /READ[ ]*=/) { facet="read"; sub(/^.*READ[ ]*=/,"",line) }
      else { facet="special"; sub(/^.*SPECIAL[ ]*=/,"",line) }
      gsub(/[,()]/," ",line)
      n=split(line, a, /[ ]+/)
      for (i=1;i<=n;i++) if (a[i] ~ /^[a-z][a-z0-9-]*$/) print facet "\t" a[i]
    }'
}

# facet_of <script> <op> — write | read | special, or empty when unlabelled.
facet_of() {
  facets_map "$1" | awk -F'\t' -v op="$2" '$2==op{print $1; exit}'
}

# own_first <cmd> [scripts...] — order so the command\'s own entity script is checked first.
own_first() {
  local cmd="$1"; shift
  local s
  [ -f "$TOOL/scripts/entities/$cmd.sh" ] && printf '%s\n' "$cmd.sh"
  for s in "$@"; do [ "$s" != "$cmd.sh" ] && printf '%s\n' "$s"; done
}

# --- resolver ------------------------------------------------------------------
# canon <name> — forgiving canonical command basename: a bare name becomes pw-<name>,
# .sh/.md tolerances applied; the full form is what gets echoed back everywhere.
canon() {
  local n="$1"
  n="${n#/}"; n="${n%.sh}"; n="${n%.md}"
  case "$n" in pw-*) : ;; *) n="pw-$n" ;; esac
  printf '%s' "$n"
}

# script_path <basename> — under entities/ or toolchain/ (never lib/: source-only,
# L2), trying the bare name and the canonical pw- form. Absolute path, or fail.
script_path() {
  local b cand
  b="${1##*/}"; b="${b%.sh}"
  for cand in "$b" "$(canon "$b")"; do
    [ -f "$TOOL/scripts/entities/$cand.sh" ] && { printf '%s' "$TOOL/scripts/entities/$cand.sh"; return 0; }
    [ -f "$TOOL/scripts/toolchain/$cand.sh" ] && { printf '%s' "$TOOL/scripts/toolchain/$cand.sh"; return 0; }
  done
  return 1
}

# scripts_of <cmd> — entity/toolchain script basenames a command file references, deduped.
scripts_of() {
  { grep -ohE '(tooling/)?scripts/(entities|toolchain)/[a-z][a-z0-9-]+\.sh' "$CMDS/$1.md" 2>/dev/null || true; } \
    | sed 's|.*/||' | sort -u
}

# --- operator surface ---------------------------------------------------------------
# The op lines are the command's own exposed surface, from two deterministic sources:
#  R1 — an entity/toolchain operator (name = usage-header sig) whose command-form
#       invocation `/pw-<cmd> <slug> <op>` appears in the command file;
#  R2 — a frontmatter selector token (C1 operator group `<a | b | c>` / `[a | b]`)
#       that appears in an invocation shape or a "literally `<tok>`" line and is not
#       already listed — command-level sugar (ai/config/item) whose script partner
#       carries a different op name (config ↔ pw-config.sh ai-review; item ↔ add-item).
selector_tokens() {
  printf '%s' "$1" | awk '{
    s=$0; depth=0; in1=0; seg=""
    for (i=1; i<=length(s); i++) { c=substr(s,i,1)
      if (c=="[" || c=="<") { depth++; if (depth==1) { in1=1; continue } }
      if (c=="]" || c==">") { if (depth==1) { if (in1 && index(seg,"|")>0) found = found seg "\n"; in1=0; seg="" }; if (depth>0) depth--; continue }
      if (in1 && depth==1) seg = seg c
    }
    if (found != "") { n=split(found, G, "\n"); for (k=1; k<=n; k++) { if (G[k]=="") continue; m=split(G[k], P, "|");
        for (q=1; q<=m; q++) { t=P[q]; sub(/^[ ]+/,"",t); sub(/[ ].*$/,"",t); if (t ~ /^[a-z][a-z0-9-]*$/) print t } } }
  }' | sort
}



# has_shape <cmd> <tok> — token appears in a real invocation span: the slash form
# `/pw-<cmd> <slug> <tok>` or a "literally `<tok>`" operator definition sentence.
# Script-form lines are NOT surface proof — C3 mapping bodies name internal steps.
has_shape() {
  local f="$CMDS/$1.md"
  grep -qF "/$1 <slug> $2 " "$f" && return 0
  grep -qF "/$1 <project-slug> $2 " "$f" && return 0
  grep -qF "/$1 <slug> $2$BT" "$f" && return 0
  grep -qF "/$1 <project-slug> $2$BT" "$f" && return 0
  grep -qF "literally $TF$2$TF" "$f" && return 0
  grep -qF "literally $BT$2$BT" "$f" && return 0
  grep -qF "literally \"$2\"" "$f" && return 0
  return 1
}

# cutw <width> — byte-safe column truncation (awk is locale-blind here): cut wide
# lines, then iconv sanitizes a mid-sequence split so output stays valid UTF-8.
cutw() {
  awk -v n="$1" '{ if (length($0) > n) print substr($0, 1, n); else print }' | iconv -f UTF-8 -t UTF-8 -c
  return 0
}

# cmd_shape_line <cmd> <tok> — the user-typed invocation args: token through the
# span-closing backtick/quote of the first command-form shape, else empty.
cmd_shape_line() {
  local ln m
  ln="$(grep -m1 -n -E "/$1[ ]+(<project-slug>|<slug>)[ ]$2([ ]|$TF|$BT|[^A-Za-z0-9-])" "$CMDS/$1.md" 2>/dev/null | cut -d: -f1 || true)"
  [ -n "$ln" ] || return 0
  m="$(awk -v ln="$ln" -v cmd="$1" 'NR==ln {
        if (match($0, cmd" (<project-slug>|<slug>) ")) { print substr($0, RSTART+RLENGTH); exit }
        if (match($0, cmd" <slug> ")) { print substr($0, RSTART+RLENGTH); exit }
      }' "$CMDS/$1.md" | head -1)"
  m="$(printf '%s' "$m" | cut -d"$TF" -f1 | cut -d"$BT" -f1 | sed -e 's/[ ]*$//')"
  printf '%s' "$m" | cutw 46
  return 0
}

# token_use_clause <cmd> <tok> — the clause a "literally `<tok>`" definition line carries.
token_use_clause() {
  local line
  line="$(grep -m1 -E "literally [$TF$BT]$2[$TF$BT]" "$CMDS/$1.md" || true)"
  [ -n "$line" ] || return 1
  printf '%s' "$line" | sed -E -e "s/.*literally [$TF$BT]$2[$TF$BT][^a-zA-Z]*//" -e 's/[.,:].*//' -e 's/^[ ]+//' | head -1 | cutw 44
}

# r2_alias <cmd> <tok> — "script<TAB>op" for a sugar token: the first REAL script
# operator invoked from the token\'s bullet block (<=9 lines under the shape).
r2_alias() {
  local cmd="$1" tok="$2" ln win pair script op sp
  ln="$(grep -m1 -n -E "/$cmd[ ]+(<project-slug>|<slug>)[ ]$tok([ ]|$TF|$BT|[^A-Za-z0-9-])" "$CMDS/$cmd.md" 2>/dev/null | cut -d: -f1 || true)"
  [ -n "$ln" ] || return 1
  win="$(sed -n "${ln},$((ln+9))p" "$CMDS/$cmd.md")"
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    script="${pair%% *}"; op="${pair##* }"
    script="${script##*/}"
    sp="$(script_path "$script" 2>/dev/null || true)" || continue
    [ -n "$sp" ] || continue
    printf '%s\n' "$(ops_of "$sp")" | grep -qx "$op" || continue
    printf '%s\t%s\n' "$script" "$op"
    return 0
  done <<EPAIRS
$(printf '%s' "$win" | grep -oE 'scripts/(entities|toolchain)/[a-z][a-z0-9-]+\.sh [a-z][a-z0-9-]*' || true)
EPAIRS
  return 1
}

# ops_surfaced <cmd> — rendered operator lines: "name<TAB>args<TAB>use<TAB>facet".
ops_surfaced() {
  local cmd="$1" text script sp op seen="$TABS" tok ali ascript aop args use fac alias_use alias_fac alias_f first_arg_flow shape_ok
  text="$(cat "$CMDS/$cmd.md")"
  case "$(fmof "$CMDS/$cmd.md" args)" in \[*|\"[\"]*) first_arg_flow=1 ;; *) first_arg_flow="" ;; esac
  # R1: real script operators whose command-form span exists.
  for script in $(own_first "$cmd" $(scripts_of "$cmd")); do
    sp="$(script_path "$script" 2>/dev/null || true)" || continue
    [ -n "$sp" ] || continue
    for op in $(ops_of "$sp"); do
      case "$seen" in *"$TABS$op$TABS"*) continue ;; esac
      has_shape "$cmd" "$op" && : || { [ -n "$first_arg_flow" ] || continue
        case "$text" in *"/$cmd $op "*|*"/$cmd $op$BT"*) : ;; *) continue ;; esac; }
      seen="$seen$op$TABS"
      args="$(cmd_shape_line "$cmd" "$op")"
      [ -n "$args" ] || args="$op $(sig_of "$sp" "$op")"
      use="$(gist "$(para_of "$sp" "$op")")"
      fac="$(facet_of "$sp" "$op")"
      printf '%s\t%s\t%s\t%s\t%s\n' "$op" "$args" "${use:-see: /pw-help operators $cmd}" "$fac" "${script}"
    done
  done
  # R2: frontmatter selector sugar ops (ai/config/item...) not already listed.
  for tok in $(selector_tokens "$(fmof "$CMDS/$cmd.md" args)"); do
    case "$seen" in *"$TABS$tok$TABS"*) continue ;; esac
    shape_ok=""
    has_shape "$cmd" "$tok" && shape_ok=1
    if [ -z "$shape_ok" ] && [ -n "$first_arg_flow" ]; then
      case "$text" in *"/$cmd $tok "*|*"/$cmd $tok$BT"*) shape_ok=1 ;; esac
    fi
    [ -n "$shape_ok" ] || continue
    seen="$seen$tok$TABS"
    args="$(cmd_shape_line "$cmd" "$tok")"; [ -n "$args" ] || args="$tok"
    use=""; fac=""
    if ali="$(r2_alias "$cmd" "$tok" 2>/dev/null || true)"; then
      ascript="${ali%%$TABS*}"; aop="${ali##*$TABS}"
      sp="$(script_path "$ascript" 2>/dev/null || true)"
      if [ -n "$sp" ]; then
        use="$(gist "$(para_of "$sp" "$aop")")"
        fac="$(facet_of "$sp" "$aop")"
      fi
    fi
    [ -n "$use" ] || use="$(token_use_clause "$cmd" "$tok" 2>/dev/null || true)"
    printf '%s\t%s\t%s\t%s\t%s\n' "$tok" "$args" "${use:-see: /pw-help operators $cmd}" "$fac" "${ascript:-$cmd.sh}"
  done
  return 0
}

# has_default <cmd> — the command file carries the no-operator flow: an invocation whose
# slug slot is followed by an optional-arg bracket or closes the span — never by an op word.
has_default() {
  local f="$CMDS/$1.md"
  grep -qE "/$1[ ]+<project-slug>[ ]*(\[|,|\.)" "$f" && return 0
  grep -qE "/$1[ ]+<slug>[ ]*(\[|,|\.)" "$f" && return 0
  grep -qF "/$1 <slug>$BT" "$f" && return 0
  grep -qF "/$1 <project-slug>$BT" "$f" && return 0
  return 1
}

did_you_mean() {
  local in="$1" c best="" bestscore=0 score i ch shared
  for c in $(cd "$CMDS" && ls *.md | sed 's/\.md$//'); do
    score=0; shared=""
    for ((i=1; i<=${#c}; i++)); do
      ch="${c:$((i-1)):1}"
      case "$in" in
        *"$ch"*) case "$shared" in *"$ch"*) : ;; *) shared="$shared$ch"; score=$((score+1)) ;; esac ;;
      esac
    done
    [ "$score" -gt "$bestscore" ] && { bestscore=$score; best="$c"; }
  done
  if [ -n "$best" ] && [ "$bestscore" -ge 6 ]; then printf 'did you mean "%s"? (list all: /pw-help overview)' "$best"
  else printf 'list all: /pw-help overview'; fi
}

# --- footer / stamp ---------------------------------------------------------------
stamp() {
  local head
  head="$(git -C "$PW_HOME" rev-parse --short HEAD 2>/dev/null || true)"
  [ -n "$head" ] || return 0
  echo "------------------------------------------------------------------------"
  echo "bundle $head - installed copies older than this? run /pw-doctor --fix"
}


# --- overview ------------------------------------------------------------------------
# Shape: bucket headers; per command a head line ("/pw-<cmd> <args>", use = frontmatter
# description sentence; op slot "(default)" when it has a default flow AND exposed ops),
# then one continuation line per surfaced operator with facet labels (S1b).
render_overview() {
  local json=0; [ "${1:-}" = "--json" ] && json=1
  local saveIFS="$IFS" ofirst=1
  local entry bucket cmd file desc args ops_lines op bargs buse bfac dflt fmfacs
  if [ "$json" = 1 ]; then printf '[\n'; else
    echo
    echo "  pw-* commands + operators - how-to per operator: /pw-help command <name>"
    echo "  ----------------------------------------------------------------------------"
  fi
  IFS=';'
  for entry in $HELP_PHASE_MAP; do
    IFS="$saveIFS"
    bucket="${entry%%|*}"
    [ "$json" = 1 ] || echo "  $bucket"
    for cmd in ${entry#*|}; do
      file="$CMDS/$cmd.md"
      [ -f "$file" ] || die "BUG: the phase map names $cmd but $CMDS/$cmd.md is missing → fix: update pw-help.sh's HELP_PHASE_MAP in the same commit as the command"
      desc="$(fmof "$file" description)"; args="$(fmof "$file" args)"
      ops_lines="$(ops_surfaced "$cmd")"
        jop=""; jonsep=""
      if [ "$json" = 1 ]; then
        [ "$ofirst" = 1 ] || printf ',\n'; ofirst=0
        fmfacs=""
        if [ -f "$TOOL/scripts/entities/$cmd.sh" ]; then
          fmfacs="$(facets_map "$TOOL/scripts/entities/$cmd.sh")"
        fi
        # build every field into its own variable: one quoted arg per %s — printf
        # argument-overflow format-repetition can then never happen.
        jc="$(jstr "$cmd")"; ja="$(jstr "$args")"; jd="$(jstr "$desc")"
        jag="$(fmof "$file" agent)"; [ -n "$jag" ] && jag="\"$(jstr "$jag")\"" || jag="null"
        jsc="$(scripts_of "$cmd" | sed 's/.*/"&"/' | paste -sd, - )"
        jfa="null"
        if [ -n "$fmfacs" ]; then
          jfw="$(printf '%s\n' "$fmfacs" | awk -F'\t' '$1=="write"{out=out sep "\"" $2 "\""; sep=", "} END{printf "%s", out}')"
          jfr="$(printf '%s\n' "$fmfacs" | awk -F'\t' '$1=="read"{out=out sep "\"" $2 "\""; sep=", "} END{printf "%s", out}')"
          jfs="$(printf '%s\n' "$fmfacs" | awk -F'\t' '$1=="special"{out=out sep "\"" $2 "\""; sep=", "} END{printf "%s", out}')"
          jfa="$(printf '{"write":[%s],"read":[%s],"special":[%s]}' "$jfw" "$jfr" "$jfs")"
        fi
        jop=""
        while IFS="$TABS" read -r jon jon2 jou jou2 jon5; do
          [ -n "$jon" ] || continue
          jop="$jop$jonsep{\"name\":\"$(jstr "$jon")\",\"use\":\"$(jstr "$jou")\",\"facet\":\"$(jstr "$jou2")\"}"
          jonsep=", "
        done <<EOPS
$ops_lines
EOPS

        printf '  {"cmd":"%s","args":"%s","summary":"%s","agent":%s,"scripts":[%s],"facets":%s,"phase":"%s","ops":[%s]}' \
          "$jc" "$ja" "$jd" "$jag" "$jsc" "$jfa" "$(jstr "$bucket")" "$jop"
        continue
      fi
      if [ -n "$ops_lines" ] && has_default "$cmd"; then dflt="(default)"; else dflt=""; fi
      printf '  %-13s %-30s %-9s - %s\n' "/pw-${cmd#pw-}" "$(printf '%s' "$args" | cutw 29)" "$dflt" "$(printf '%s' "$(gist "$desc")" | cutw 40)"
      while IFS="$TABS" read -r op bargs buse bfac bscript; do
        [ -n "$op" ] || continue
        printf '  %-13s %-30s %-9s - %s\n' "" "$(printf '%s' "$bargs" | cutw 29)" \
          "$( [ -n "$bfac" ] && printf '(%s)' "$bfac" | cutw 8 )" "$(printf '%s' "$buse" | cutw 40)"
      done <<EOPS
$ops_lines
EOPS
    done
    IFS=';'
  done
  IFS="$saveIFS"
  if [ "$json" = 1 ]; then printf '\n]\n'; else stamp; fi
}

# --- command how-to --------------------------------------------------------------------
# cmd_block <cmd> <tok> — the bullet block a command file carries for a token
# (its own shape line through the next bullet / heading), markdown included —
# the human-facing prose is lifted verbatim, never re-written.
cmd_block() {
  local cmd="$1" tok="$2" ln
  ln="$(grep -m1 -n -E "/$cmd[ ]+(<project-slug>|<slug>)[ ]$tok([ ]|$TF|$BT|[^A-Za-z0-9-])|^If the 2nd argument is literally [$TF$BT]$tok[$TF$BT]" "$CMDS/$cmd.md" 2>/dev/null | cut -d: -f1 || true)"
  [ -n "$ln" ] || return 0
  awk -v from="$ln" 'NR<from{next} NR>from && (/^- \*\*/ || /^## / || /^[0-9]+\. \*\*/){exit} NR>=from{print}' "$CMDS/$cmd.md"
}

strip_md() { sed -e 's/\*\*//g' -e 's/\*//g' -e 's/`//g' -e 's/^[ >-]\{1,3\}//' -e 's/^[[:space:]]*//'; }

render_command() {
  [ $# -ge 1 ] || die "usage: command <name> [<slug>] [--full|--json] → fix: bare /pw-help lists every command"
  local name slug="" flags="" a full=0 json=0
  name="$1"; shift
  for a in "$@"; do
    case "$a" in
      --full) full=1 ;;
      --json) json=1 ;;
      -*) flags="$flags $a" ;;
      *) [ -n "$name" ] && slug="$a" || name="$a" ;;
    esac
  done
  local c; c="$(canon "$name")"
  local file="$CMDS/$c.md"
  [ -f "$file" ] || die "no such command: $(canon "$name") → fix: $(did_you_mean "$c")"
  local desc args agn
  desc="$(fmof "$file" description)"; args="$(fmof "$file" args)"; agn="$(fmof "$file" agent)"

  if [ "$full" = 1 ]; then
    awk 'c==2{print} $0=="---"{c++}' "$file" | sub
    return 0
  fi

  local ops_lines; ops_lines="$(ops_surfaced "$c")"
  if [ "$json" = 1 ]; then
    local o_name o_args o_use o_fac bloc jops="" sep=""
    while IFS="$TABS" read -r o_name o_args o_use o_fac; do
      [ -n "$o_name" ] || continue
      jops="$jops$sep{\"name\":\"$(jstr "$o_name")\",\"args\":\"$(jstr "$o_args")\",\"use\":\"$(jstr "$o_use")\",\"facet\":\"$(jstr "$o_fac")\"}"
      sep=", "
    done <<E
$ops_lines
E
    printf '{"cmd":"%s","args":"%s","summary":"%s","agent":%s,"ops":[%s],"scripts":[%s]}
' \
      "$(jstr "$c")" "$(jstr "$args")" "$(jstr "$desc")" \
      "$( [ -n "$agn" ] && printf '"%s"' "$(jstr "$agn")" || printf 'null' )" \
      "$jops" "$(scripts_of "$c" | sed 's/.*/"&"/' | paste -sd, - )"
    return 0
  fi

  echo "/pw-${c#pw-} — $desc"
  echo "args: $args"
  [ -n "$agn" ] && echo "agent lane: $agn"
  [ -n "$slug" ] && echo "project: $slug"
  echo
  # (default) flow line — args with the operator-selector group removed, slug-filled.
  if has_default "$c"; then
    local dargs
    dargs="$(printf '%s' "$args" | sed -E -e 's/<[^<>]*\|[^<>]*>//g' -e 's/\[[^][]*\|[^][]*\]//g' -e 's/  +/ /g' -e 's/[ ;.]+$//')"
    dargs="${dargs#<project-slug> }"; dargs="${dargs#<slug> }"
    printf '  (default)  /pw-%s %s %s\n' "${c#pw-}" "${slug:-<project-slug>}" "$dargs"
    printf '    Use:     the no-operator default flow - see the args line above\n'
  fi
  local bname bargs buse bfac bscript sp2 par usep
  while IFS="$TABS" read -r bname bargs buse bfac bscript; do
    [ -n "$bname" ] || continue
    printf '  %s  %s\n' "$(printf '%-11s' "$bname")" "$(printf '%s' "${bargs#$bname }" | cutw 68)"
    # The command file's OWN bullet prose = use-when behavior; the script paragraph = Does.
    local bloc
    bloc="$(cmd_block "$c" "$bname" | strip_md | sub)"
    # the human prose = block text after the first em-dash (the mapping arrow prefix
    # ends in "—"); joined, collapsed.
    usep="$(printf '%s' "$bloc" | awk '{ s=s $0 " " } END { i=index(s,"—"); if (i) { s=substr(s,i); sub(/^—/,"",s) }; gsub(/[ ]+/," ",s); sub(/^ /,"",s); sub(/ $/,"",s); print s }')"
    sp2="$(script_path "$bscript" 2>/dev/null || true)"
    par=""; [ -n "$sp2" ] && par="$(para_of "$sp2" "$bname")"
    [ -n "$par" ] || par="$buse"
    if [ -n "$usep" ] && [ "$usep" != "$par" ]; then
      printf '%s\n' "$usep" | fold -s -w 90 | sed 's/^/    Use when: /' | head -6
    fi
    printf '%s\n' "$par" | fold -s -w 90 | sed 's/^/    Does:   /' | head -6
    printf '%s\n' "$bloc" | awk '/DOCTRINE|HUMAN-TRIGGERED ONLY/{print "    " $0}' | head -2 | cutw 96 || true
    { printf '%s\n' "$bloc" | grep -oE 'A[12] [a-zA-Z][^`)”]*' | head -1 | sed 's/^/    Shape:  /' | cutw 96; } || true
    printf '    $ %s\n' "$(cutw 90 <<<"/pw-${c#pw-} ${slug:-<project-slug>} $bargs" | sed -e 's/[ ]*$//')"
  done <<E
$ops_lines
E
  [ -n "$ops_lines" ] || printf '  (single flow - no operator dispatch on this command)\n'
  echo
  local script sp nops
  for script in $(own_first "$c" $(scripts_of "$c")); do
    sp="$(script_path "$script" 2>/dev/null || true)"; [ -n "$sp" ] || continue
    nops="$(ops_of "$sp" | wc -l | tr -d ' ')"
    echo "entity script: ${sp#$PW_HOME/} ($nops operators — read all: /pw-help operators ${script%.sh})"
    facets_map "$sp" | awk -F'\t' '{ facet_of[$2]=$1 } END { }' >/dev/null
    while IFS= read -r o; do
      [ -n "$o" ] || continue
      f="$(facet_of "$sp" "$o")"
      printf '    %-8s %-26s %s\n' "$f" "$o" "$(sig_of "$sp" "$o" | cutw 50)"
    done <<EO
$(ops_of "$sp")
EO
  done
  grep -oE '(tooling/)?docs/[A-Za-z0-9._/-]+\.md' "$file" | sort -u | sed 's|^|doc: |'
  grep -qF 'mechanical mapping (C3)' "$file" && echo "doctrine: mechanical mapping (C3) — the script is the single judgment point."
  stamp
}

# --- operators (deep dump) --------------------------------------------------------------
render_operators() {
  [ $# -ge 1 ] || die "usage: operators <name> [<operator>] → fix: bare /pw-help lists every command"
  local name="$1" op="${2:-}" c sp scripts="" s found="" facet
  c="$(canon "$name")"
  if [ -f "$CMDS/$c.md" ]; then
    for sp in $(scripts_of "$c"); do
      sp="$(script_path "$sp" 2>/dev/null)" || continue
      scripts="$scripts$sp
"
    done
  elif sp="$(script_path "$name" 2>/dev/null || true)" && [ -n "$sp" ]; then
    scripts="$sp
"
  else
    die "no such command or script: $c → fix: $(did_you_mean "$c")"
  fi
  [ -n "$scripts" ] || die "command $c wires no entity/toolchain script → fix: read $CMDS/$c.md"
  if [ -n "$op" ]; then
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      printf '%s\n' "$(ops_of "$s")" | grep -qx "$op" || continue
      found="yes"
      printf '%s :: %s %s\n' "$(basename "$s")" "$op" "$(sig_of "$s" "$op")"
      para_of "$s" "$op" | fold -s -w 92 | sed 's/^/    /'
      facet="$(facet_of "$s" "$op")"
      [ -n "$facet" ] && printf '    (facet: %s)\n' "$facet"
    done <<E
$scripts
E
    [ -n "$found" ] || die "no such operator \"$op\" in $c → fix: /pw-help operators $c lists all operators"
  else
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      echo "== $(basename "$s") =="
      hdr_lines "$s" | sub
      echo
    done <<E
$scripts
E
  fi
  stamp
}

# --- workflow ---------------------------------------------------------------------------
render_workflow() {
  local json=0; [ "${1:-}" = "--json" ] && json=1
  local phase line gate first=1
  [ "$json" = 1 ] && printf '{"phases":['
  for phase in $PW_VALID_PHASES; do
    case "$phase" in
      context)   line="/pw-new · /pw-adopt · fill context/ (+ /pw-context add-input rows)" ; gate="" ;;
      analysis)  line="/pw-research (optional) · /pw-analyze" ; gate="analysis/review/<topic>.review.md sign-off" ;;
      breakdown) line="/pw-breakdown" ; gate="THE hard gate: task/review/PLAN.review.md (+ per-task reviews)" ;;
      executing) line="/pw-execute · /pw-verify · /pw-sync" ; gate="worktree sub-agents, verified commits" ;;
      review)    line="/pw-ship · comment loop back through /pw-review · re-sync when the base moves" ; gate="MR open + comments folded into the review docs" ;;
      done)      line="/pw-close" ; gate="teardown, learnings, Status: done" ;;
      *)         line="?" ; gate="" ;;
    esac
    if [ "$json" = 1 ]; then
      [ "$first" = 1 ] || printf ',' ; first=0
      printf '{"phase":"%s","cmds":"%s","gate":"%s"}' "$phase" "$(jstr "$line")" "$(jstr "$gate")"
    else
      printf '%-11s %s\n' "$phase" "$line"
      [ -n "$gate" ] && printf '            gate: %s\n' "$gate"
    fi
  done
  if [ "$json" = 1 ]; then
    printf ']}\n'
  else
    echo
    echo "side-loop   /pw-rfc after any gate-approved content"
    echo "any-time    /pw-status · /pw-help · /pw-doctor"
    stamp
  fi
}

# --- usage / dispatch ------------------------------------------------------------------------
usage() {
  cat <<'EOF'
usage: pw-help.sh <operator> [args] [--json]

  overview                    one line per command and per exposed operator
  command <name> [<slug>]     how-to manual for one command (--full = verbatim file)
  operators <name> [<op>]     verbatim usage-header dump (or one operator deep-dive)
  workflow                    the phase spine with gates
  --selftest                  run the isolated harness case
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then usage; exit 0; fi

op0="${1:-overview}"
case "$op0" in
  overview)   shift; render_overview "$@" ;;
  command)    shift; render_command "$@" ;;
  operators) shift; render_operators "$@" ;;
  workflow)  shift; render_workflow "$@" ;;
  *)         usage >&2; die "unknown operator: $op0 → fix: bare /pw-help lists every command" ;;
esac
