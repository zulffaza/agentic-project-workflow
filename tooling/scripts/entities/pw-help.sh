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
#       pointers, and the frontmatter summary. --maintainer adds the entity-script
#       sections (paths + operator signatures) and tooling/docs pointers — the user
#       view is command surface only. With <slug> the invocation slots
#       show that slug. --full renders the entire command file (placeholders
#       substituted) for the rare reader that needs the doctrine verbatim.
#
#   pw-help.sh project    <slug> [<name>] [--json]
#       Project-specific how-to: current phase (read via the state reader), the
#       most-likely-next command lines filled with THIS project's real targets,
#       the review/plan/task files found on disk with gate states and open-item
#       counts, and (with <name>) one command's operators concretized against
#       those targets. The state-rich report stays /pw-status - this view answers
#       "what do I run now, with what exact arguments".
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
#   pw-help.sh find       <term...> [--json]
#       Bounded discovery grep across the caller-visible surfaces (tooling commands,
#       entity + toolchain script usage headers, tooling docs + root docs) — never
#       library sources, never corpus projects. The term(s) are ONE literal
#       case-insensitive phrase (rest-of-line, A1); matches print surface-grouped
#       file:line with a trimmed snippet, capped at 20 plus a how-to-narrow tail.
#       Zero hits is a RESULT, not an error (exit 0). It is a pointer, not a reader:
#       deep content is the command view, doctrine is the command file.
#       Agents: --json returns [{surface,path,line,text}] — one cheap bounded call
#       beats exploratory greps to locate a concept across the tooling surface set.
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
# the READ-ONLY subprocess trio (the §3.4.1 whitelist; the T1 case pins it mechanically):
ST="$HERE/pw-status.sh"
RV="$HERE/pw-review.sh"
CFG="$HERE/pw-config.sh"

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

# fwrap <width> — greedy word-wrap on stdin; one full logical line in, n short lines
# out. Nothing is ever cut — overflow flows to the next line.
fwrap() {
  awk -v w="$1" '{
    n=split($0,W," "); buf=""
    for (i=1;i<=n;i++) { if (W[i]=="") continue
      cand = (buf=="") ? W[i] : buf " " W[i]
      if (buf!="" && length(cand) > w) { print buf; buf = W[i] } else buf = cand }
    print buf
  }'
  return 0
}

# flowline <width> — keep a composed line's content whole: overflow wraps onto
# continuation lines marked " + " (never past the width; short lines pass 1:1).
flowline() {
  awk -v w="$1" '
  { l=$0
    if (length(l) <= w) { print; next }
    first=1
    while (length(l) > w) {
      lim = w
      if (!first) lim = w - 3
      pos=0
      for (k=lim; k>0; k--) { if (substr(l,k,1)==" ") { pos=k; break } }
      if (pos==0) pos=lim
      seg=substr(l,1,pos-1)
      if (first) { print seg; first=0 } else { print " + " seg }
      l=substr(l,pos+1)
      sub(/^ +/,"",l)
    }
    if (l != "") {
      if (first) { print l } else { print " + " l }
    }
  }'
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
  printf '%s' "$m"
  return 0
}

# token_use_clause <cmd> <tok> — the clause a "literally `<tok>`" definition line carries.
token_use_clause() {
  local line
  line="$(grep -m1 -E "literally [$TF$BT]$2[$TF$BT]" "$CMDS/$1.md" || true)"
  [ -n "$line" ] || return 1
  printf '%s' "$line" | sed -E -e "s/.*literally [$TF$BT]$2[$TF$BT][^a-zA-Z]*//" -e 's/[.,:].*//' -e 's/^[ ]+//' | head -1
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

# fwrap <width> — one logical line in, word-wrapped lines <=w bytes out;
# nothing is ever cut — text flows onto the next line.
fwrap() {
  awk -v w="$1" '{
    n=split($0,W," "); buf=""
    for (i=1;i<=n;i++) { if (W[i]=="") continue
      cand = (buf=="") ? W[i] : buf " " W[i]
      if (buf!="" && length(cand) > w) { print buf; buf = W[i] } else buf = cand }
    print buf
  }'
  return 0
}

# ov_wrap <prefix1> <prefixN> — greedy word-wrap emitting each line as prefix+text,
# keeping the FULL 98-byte budget per line against the actual prefix lengths (an
# inline-label shift never overflows).
ov_wrap() {
  awk -v p1="$1" -v p2="$2" '{
    n=split($0,Wd," "); cur=""; first=1
    for (k=1;k<=n;k++) { if (Wd[k]=="") continue
      w=Wd[k]
      lim = 98 - (first ? length(p1) : length(p2))
      # over-long single token (paths): break at the last punctuation inside the limit
      while (length(w) > lim) {
        if (cur != "") { print (first ? p1 : p2) cur; first=0; cur="" }
        cut=0
        for (j=lim; j>1; j--) { ch=substr(w,j,1); if (ch=="/" || ch==":" || ch=="-" || ch==".") { cut=j; break } }
        if (cut<2) cut=lim
        print (first ? p1 : p2) substr(w,1,cut); first=0; w=substr(w,cut+1)
        lim = 98 - length(p2)
      }
      cand = (cur=="") ? w : cur " " w
      lim = 98 - (first ? length(p1) : length(p2))
      if (cur!="" && length(cand) > lim) { print (first ? p1 : p2) cur; first=0; cur=w }
      else cur = cand }
    if (cur != "") print (first ? p1 : p2) cur
  }'
  return 0
}
# ov_emit <cmd-label> <tag> <args> <use> — one overview entry: a fitted single line
# when the UNTRUNCATED args (<=29) and use stay under 98 cols together; otherwise a
# block: args fully wrapped from the args column, use text beneath it, continuations
# marked "+ ". Nothing is cut, nothing is ellipsized — it just flows.
ov_emit() {
  local lbl="$1" tag="$2" args="$3" use="$4" line
  case "$tag" in write|read|special|lifecycle) tag="($tag)" ;; '(default)'|""|"(sugar)") : ;; *) tag="" ;; esac
  line="$(printf '  %-13s %-29s %-13s- %s\n' "$lbl" "$args" "${tag:+$tag }" "$use")"
  if printf '%s' "$line" | awk -v n=98 'length($0)<=n{exit 0} {exit 1}' \
     && printf '%s' "$args" | awk -v n=29 'length($0)<=n{exit 0} {exit 1}'; then
    printf '%s\n' "$line"
    return 0
  fi
  if [ -n "$args" ]; then
    printf '%s\n' "$args" | ov_wrap "$(printf '  %-13s ' "$lbl")" "                + "
  else
    printf '  %s\n' "$lbl"
  fi
  printf '%s\n' "$use" | ov_wrap "                  ${tag:+$tag }- " "                  + "
  return 0
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
      ov_emit "/pw-${cmd#pw-}" "$dflt" "$args" "$(gist "$desc")"
      while IFS="$TABS" read -r op bargs buse bfac bscript; do
        [ -n "$op" ] || continue
        ov_emit "" "$bfac" "$bargs" "$buse"
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
  local name slug="" flags="" a full=0 json=0 mant=0
  name="$1"; shift
  for a in "$@"; do
    case "$a" in
      --full) full=1 ;;
      --json) json=1 ;;
      --maintainer) mant=1 ;;
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

  { printf '/pw-%s - %s\n' "${c#pw-}" "$desc"; } | flowline 98
  { printf 'args: %s\n' "$args"; } | flowline 98
  [ -n "$agn" ] && { printf 'agent lane: %s\n' "$agn"; } | flowline 98
  [ -n "$slug" ] && { printf 'project: %s\n' "$slug"; } | flowline 98
  echo
  # (default) flow line — args with the operator-selector group removed, slug-filled.
  if has_default "$c"; then
    local dargs
    dargs="$(printf '%s' "$args" | sed -E -e 's/<[^<>]*\|[^<>]*>//g' -e 's/\[[^][]*\|[^][]*\]//g' -e 's/  +/ /g' -e 's/[ ;.]+$//')"
    dargs="${dargs#<project-slug> }"; dargs="${dargs#<slug> }"
    printf '  (default)  /pw-%s %s %s\n' "${c#pw-}" "${slug:-<project-slug>}" "$dargs" | flowline 98
    printf '    Use:     the no-operator default flow - see the args line above\n'
  fi
  local bname bargs buse bfac bscript sp2 par usep
  while IFS="$TABS" read -r bname bargs buse bfac bscript; do
    [ -n "$bname" ] || continue
    printf '  %s  %s\n' "$(printf '%-11s' "$bname")" "${bargs#$bname }" | flowline 98
    # The command file's OWN bullet prose = use-when behavior; the script paragraph = Does.
    local bloc
    bloc="$(cmd_block "$c" "$bname" | strip_md | sub | awk '/^[ \t]*[0-9]+[.)]/{exit} { line=$0; p=index(line,"/Users/"); if (!p) p=index(line,"tooling/scripts/"); if (p) { pre=substr(line,1,p-1); gsub(/[ \t\-`→—]+$/,"",pre); if (pre=="") next; print pre; next } print }')"
    # the human prose = block text after the first em-dash (the mapping arrow prefix
    # ends in "—"); joined, collapsed.
    usep="$(printf '%s' "$bloc" | awk '{ s=s $0 " " } END { i=index(s,"—"); j2=index(s,"→"); if (i) { s=substr(s,i); sub(/^—[ ]?/,"",s) } else if (j2) { s=substr(s,j2); sub(/^→[ ]?/,"",s) }; j=index(s,"If the 2nd argument"); if (j) s=substr(s,1,j-1); gsub(/[ ]+/," ",s); sub(/ +$/,"",s); sub(/[ ]*(Run|run)[ ]*:?[ ]*$/,"",s); do { s2=s; sub(/[ ]+(to|of|in|is|that|and|or|the|a|an|for|with|on|at|by|as|into|through|pass|flags?|from|via)$/,"",s) } while (s!=s2); sub(/[ :,.]+$/,"",s); if (s ~ /^[a-z0-9(<]/ && length(s) < 30 && s !~ /[.;:]/) s=""; print s }')"
    sp2="$(script_path "$bscript" 2>/dev/null || true)"
    par=""; [ -n "$sp2" ] && par="$(para_of "$sp2" "$bname")"
    [ -n "$par" ] || par="$buse"
    if [ -n "$usep" ] && [ "$usep" != "$par" ]; then
      printf '%s\n' "$usep" | ov_wrap "    Use when: " "             + "
    fi
    printf '%s\n' "$par" | ov_wrap "    Does:   " "             + "
    printf '%s\n' "$bloc" | awk '/DOCTRINE|HUMAN-TRIGGERED ONLY/{print "    " $0}' | head -2 | flowline 98 || true
    { printf '%s\n' "$bloc" | grep -oE 'A[12] [a-zA-Z][^`)”]*' | head -1 | sed 's/^/    Shape:  /' | flowline 98; } || true
    printf '    $ %s\n' "/pw-${c#pw-} ${slug:-<project-slug>} $bargs" | sed -e 's/[ ]*$//' | flowline 98
  done <<E
$ops_lines
E
  [ -n "$ops_lines" ] || printf '  (single flow - no operator dispatch on this command)\n'
  echo
  local script sp nops
  if [ "$mant" = 1 ]; then
  for script in $(own_first "$c" $(scripts_of "$c")); do
    sp="$(script_path "$script" 2>/dev/null || true)"; [ -n "$sp" ] || continue
    nops="$(ops_of "$sp" | wc -l | tr -d ' ')"
    printf 'entity script: %s (%s operators - read all: /pw-help operators %s)\n' "${sp#$PW_HOME/}" "$nops" "${script%.sh}" | flowline 98
    facets_map "$sp" | awk -F'\t' '{ facet_of[$2]=$1 } END { }' >/dev/null
    while IFS= read -r o; do
      [ -n "$o" ] || continue
      f="$(facet_of "$sp" "$o")"
      printf '    %-8s %-26s %s\n' "$f" "$o" "$(sig_of "$sp" "$o")" | flowline 98
    done <<EO
$(ops_of "$sp")
EO
  done
  fi
  [ "$mant" = 1 ] || echo "  (user view - entity scripts and their operators: /pw-help operators $c, or command view with --maintainer)"
  local dpaths dpl
  dpaths="$(grep -oE '(tooling/)?docs/[A-Za-z0-9._/-]+\.md' "$file" | sort -u || true)"
  while IFS= read -r dpl; do
    [ -n "$dpl" ] || continue
    if [ "$mant" != 1 ]; then case "$dpl" in tooling/*) continue ;; esac; fi
    printf 'doc: %s\n' "$dpl"
  done <<EDOC
$dpaths
EDOC
  grep -qF 'mechanical mapping (C3)' "$file" && { echo "doctrine: mechanical mapping (C3) - the script is the single judgment point."; } | flowline 98
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


# --- find -------------------------------------------------------------------------------
find_surfaces() { # ordered "label<TAB>root" sources (L2: libraries excluded by design)
  printf 'cmd\t%s\n' "$TOOL/commands"
  printf 'script\t%s/scripts/entities\n' "$TOOL"
  printf 'script\t%s/scripts/toolchain\n' "$TOOL"
  printf 'tooling-doc\t%s/docs\n' "$TOOL"
  printf 'doc\t%s/../docs\n' "$TOOL"
}

render_find() {
  local json=0 a phrase
  set -f
  local -a args=(); for a in "$@"; do case "$a" in --json) json=1 ;; *) args=("${args[@]+"${args[@]}"}" "$a") ;; esac; done
  set +f
  [ "${#args[@]}" -gt 0 ] || die "find: no search term -> fix: /pw-help find sign-off (one literal phrase)"
  phrase="${args[*]}"
  local label root hits
  hits="$(mktemp)"
  while IFS="$TABS" read -r label root; do
    [ -d "$root" ] || continue
    grep -rinF --include='*.sh' --include='*.md' -- "$phrase" "$root" 2>/dev/null \
      | sed -e "s|^|${label}@@|" >> "$hits" || true
  done <<EF
$(find_surfaces)
EF
  local total
  total="$(awk 'END{print NR+0}' "$hits")"
  # path normalization + snippet trim -> uniform records "surface PATH LINE TEXT"
  local norm; norm="$(mktemp)"
  python3 - "$hits" "$PW_HOME" <<'PYNORM' > "$norm"
import sys
root, home = sys.argv[1], sys.argv[2] + "/"
out=[]
for line in open(root, encoding='utf-8', errors='replace'):
    surf, _, rest = line.partition('@@')
    rest = rest.rstrip('\n')
    path, ln, text = rest.split(':', 2)
    if path.startswith(home): path = path[len(home):]
    out.append((surf, path, ln, text.strip()[:60]))
import json
for surf, path, ln, text in out:
    print(f"{surf}\t{path}\t{ln}\t{text}")
PYNORM
  local n=0
  if [ "$json" = 1 ]; then
    local first=1
    printf '['
    while IFS="$TABS" read -r surf pth ln txt; do
      [ "$first" = 1 ] || printf ','; first=0
      printf '{"surface":"%s","path":"%s","line":%s,"text":"%s"}' "$(jstr "$surf")" "$(jstr "$pth")" "$ln" "$(jstr "$txt")"
    done < "$norm"
    printf ']\n'
    rm -f "$hits" "$norm"
    return 0
  elif [ "${total:-0}" = "0" ]; then
    echo "(no matches) - the term is one literal phrase; try a single word, or just /pw-help"
  else
    while IFS="$TABS" read -r surf pth ln txt; do
      n=$((n+1)); [ "$n" -le 20 ] || break
      printf '  %-12s %s:%s  %s\n' "$(cutw 11 <<<"$surf")" "$pth" "$ln" "$(cutw 60 <<<"$txt")"
    done < "$norm"
    [ "$n" -le 20 ] || printf '  (%s more - narrow the phrase, or the how-to view: /pw-help command <name>)\n' "$((total-20))"
  fi
  rm -f "$hits" "$norm"
  stamp
}

# --- usage / dispatch ------------------------------------------------------------------------

# --- project-specific view ------------------------------------------------------------------
# proj_dir mirrors the sibling entities' helper (die text in pw-help voice, full names).
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "project not found under $PROJECTS_DIR/$1 -> fix: scaffold it with /pw-new $1, or check /pw-status $1"; printf '%s' "$d"; }

# review_state <slug> <rel> — "<decision>|<open-count>" via the read operators only.
review_state() {
  local slug="$1" rel="$2" dec cnt
  dec="$(PW_PROJECTS_DIR="$PROJECTS_DIR" "$RV" gate "$slug" "$rel" 2>/dev/null | pw_phase_token)" || true
  case "$dec" in "") dec="none yet" ;; approved|changes-requested|in-review) : ;; *) dec="pending" ;; esac
  cnt="$(PW_PROJECTS_DIR="$PROJECTS_DIR" "$RV" count "$slug" "$rel" 2>/dev/null)" || cnt="open=?"
  printf '%s|%s' "$dec" "$(printf '%s' "$cnt" | sed -e 's/^open=//' -e 's/ resolved=[0-9]*//' -e 's/ items=[0-9]*//')"
}

# render_project_next <slug> <phase> <plan> <planrev> <dir> <plain|json>
render_project_next() {
  local slug="$1" phase="$2" plan="$3" planrev="$4" mode="$6"
  local lines l first=1 a
  case "$phase" in
    context)
      lines="/pw-context $slug req-init                            (then fill it + register provenance rows)
/pw-analyze $slug                                      create analysis/<topic>.md (+ its review sibling)" ;;
    analysis)
      lines="/pw-review $slug ...                                   item/answer/sign-off your analysis reviews (targets above)
/pw-breakdown $slug                                      approved analysis -> task/PLAN.md + T0n files" ;;
    breakdown)
      if [ -z "$plan" ]; then
        lines="/pw-breakdown $slug                                      no task/PLAN.md yet: get the analysis gates approved first (see targets + fix hints)"
      elif [ -z "$planrev" ]; then
        lines="/pw-review $slug init-all                                review file for PLAN.md missing - create it first
       (then: item / answer / signoff on task/review/PLAN.review.md, then /pw-execute $slug)"
      else
        lines="/pw-review $slug item $planrev §2 <your ask>   file a review item (auto Rn)
/pw-review $slug signoff $planrev <your decision>   HUMAN-TRIGGERED ONLY (C4)
       (decision is one of: approved | changes-requested | in-review)
/pw-execute $slug                                              after the plan gate approves"
      fi ;;
    executing)
      lines="/pw-verify   T0n                                        independent check of ONE change
/pw-sync $slug                                               merge when the base branch moved
/pw-ship $slug                                               push verified task branches + open MRs" ;;
    review)
      lines="/pw-review $slug                                       apply comments folded back from the MR
/pw-ship $slug comments                                     pull new MR comments in
/pw-sync $slug                                               re-sync when the base moves" ;;
    done)
      lines="/pw-close $slug                                         teardown, learnings, Status: done" ;;
    *)
      lines="/pw-status $slug                                        (phase token unparseable - check the README.md Status: line)" ;;
  esac
  if [ "$mode" = json ]; then
    { local done2=0; while IFS= read -r l; do [ "$done2" = 1 ] && printf ','; done2=1; printf '"%s"' "$(jstr "$l")"; done <<EXN
$lines
EXN
    }
    return 0
  fi
  printf '%s\n' "$lines" | flowline 98
}

render_project_cmd() {
  local slug="$1" phase="$2" name="$3" plan="$4" planrev="$5" adocs="$6" trevs="$7" d="$9"
  local c; c="$(canon "$name")"
  [ -f "$CMDS/$c.md" ] || die "no such command: $c -> fix: $(did_you_mean "$c")"
  if [ "$c" = "pw-review" ]; then
    local rel rvf st sep=""
    echo "/pw-review targets in $slug (phase: $phase; live gate/open states below)"
    echo "  gates:"
    for rel in $planrev; do st="$(review_state "$slug" "$rel")"; printf '    %-42s decision: %-19s open: %s\n' "$rel" "${st%%|*}" "${st##*|}"; done
    for rel in $adocs; do
      rvf="analysis/review/${rel#analysis/}"; rvf="${rvf%.md}.review.md"
      [ -f "$d/$rvf" ] && { st="$(review_state "$slug" "$rvf")"; printf '    %-42s decision: %-19s open: %s\n' "$rvf" "${st%%|*}" "${st##*|}"; } || true
    done
    [ -n "$planrev$adocs" ] || echo "    (no review files yet - run: /pw-review $slug init-all)"
    echo "  items:"
    local revlist="$planrev" arel shown=0
    for arel in $adocs; do rvf="analysis/review/${arel#analysis/}"; rvf="${rvf%.md}.review.md"; [ -f "$d/$rvf" ] && revlist="$revlist $rvf" || true; done
    [ -n "$trevs" ] && revlist="$revlist $trevs"
    for rvf in $revlist; do
      [ -f "$d/$rvf" ] || continue
      if grep -oE '^### (Q|R)[0-9]+.*\[(PENDING|OPEN)\]' "$d/$rvf" 2>/dev/null | head -3 | cut -c5- | sed "s|^|      $rvf  |" | flowline 96 | grep -q .; then shown=1; fi
    done
    [ "$shown" = 1 ] || echo "      (no open items / pending questions in the review files found)"
    echo "  runnable:"
    printf '    /pw-review %s item %s §3 <your ask>\n' "$slug" "${planrev:-task/review/PLAN.review.md}"
    printf '    /pw-review %s signoff %s <your decision>   HUMAN-TRIGGERED ONLY (C4)\n' "$slug" "${planrev:-task/review/PLAN.review.md}"
    printf '           (decision is one of: approved | changes-requested | in-review)\n'
    local cfgs
    cfgs="$(PW_PROJECTS_DIR="$PROJECTS_DIR" "$CFG" ai-review "$slug" 2>/dev/null | tr '\n' ' ')"
    [ -n "$cfgs" ] || cfgs="-"
    printf '    /pw-review %s ai          second opinion (modes: %s)\n' "$slug" "$cfgs" | flowline 98
    printf '    /pw-review %s config analysis <approved mode>   (off|advisory|auto)\n' "$slug"
    stamp; return 0
  fi
  echo "/pw-${c#pw-} for $slug (phase: $phase)"
  local op args2 use2 fac2 s5
  while IFS="$TABS" read -r op args2 use2 fac2 s5; do
    [ -n "$op" ] || continue
    printf '    /pw-%s %s %s\n' "${c#pw-}" "$slug" "$args2"
  done <<EPCC
$(ops_surfaced "$c")
EPCC
  stamp
}

render_project() {
  [ $# -ge 1 ] || die "usage: project <slug> [<name>] [--json] -> fix: bare /pw-help overview for the global view"
  local slug="$1"; shift || true
  local name="${1:-}" a json=0
  [ "$name" = "--json" ] && { json=1; name=""; }
  local d; d="$(proj_dir "$slug")"
  local raw tok
  raw="$(PW_PROJECTS_DIR="$PROJECTS_DIR" "$ST" phase "$slug" 2>/dev/null)" || raw="?"
  tok="$(pw_phase_token "$raw")"
  local plan="" planrev="" adocs="" trevs="" tids f rel rvf
  [ -f "$d/task/PLAN.md" ] && plan="task/PLAN.md" || true
  [ -f "$d/task/review/PLAN.review.md" ] && planrev="task/review/PLAN.review.md" || true
  for f in "$d"/analysis/*.md; do
    [ -f "$f" ] || continue
    rel="analysis/${f##*/}"; case "$rel" in *review/*) continue ;; esac
    adocs="$adocs $rel"
  done
  for f in "$d"/task/review/T*.review.md; do [ -f "$f" ] && trevs="$trevs task/review/${f##*/}" || true; done
  for f in "$d"/task/T[0-9][0-9].md; do [ -f "$f" ] && tids="$tids ${f##*.md}"; done

  case "$name" in ""|--json) : ;; *) render_project_cmd "$slug" "$tok" "$name" "$plan" "$planrev" "$adocs" "$trevs" "$tids" "$d"; return 0 ;; esac

  local tail st sep=""
  tail="${raw#"$tok"}"; tail="$(printf '%s' "$tail" | sed -e 's/^[ ]*//' -e 's/^[([]//' -e 's/[])?]$//')"
  if [ "$json" = 1 ]; then
    printf '{"slug":"%s","phase":"%s","status":"%s","targets":[' "$(jstr "$slug")" "$(jstr "$tok")" "$(jstr "$raw")"
    for rel in $planrev; do st="$(review_state "$slug" "$rel")"; printf '%s{"doc":"task/PLAN.md","review":"%s","gate":"%s","open":"%s"}' "$sep" "$(jstr "$rel")" "$(jstr "${st%%|*}")" "$(jstr "${st##*|}")"; sep=", "; done
    for rel in $adocs; do
      rvf="analysis/review/${rel#analysis/}"; rvf="${rvf%.md}.review.md"
      if [ -f "$d/$rvf" ]; then st="$(review_state "$slug" "$rvf")"; printf '%s{"doc":"%s","review":"%s","gate":"%s","open":"%s"}' "$sep" "$(jstr "$rel")" "$(jstr "$rvf")" "$(jstr "${st%%|*}")" "$(jstr "${st##*|}")"; sep=", "; fi
    done
    local jtasks=""
    if [ -n "$tids" ]; then jtasks="$(printf '%s' "${tids# }" | sed -e 's/ /", "/g' | sed -e 's/^/"/' -e 's/$/"/')"; fi
    printf '],"next":[%s],"tasks":[%s]}\n' "$(render_project_next "$slug" "$tok" "$plan" "$planrev" "$d" json)" "$jtasks"
    return 0
  fi
  { printf '%s - phase: %s' "$slug" "$tok"; [ -n "$tail" ] && printf '  (%s)' "$tail"; echo; } | flowline 98
  echo
  echo "most likely next:"
  render_project_next "$slug" "$tok" "$plan" "$planrev" "$d" plain
  echo "any-time for this project:"
  echo "  /pw-status $slug  ·  /pw-context $slug add-input --file ... --what ... --source ..."
  echo "targets found on disk:"
  local trow printed=0
  trow() { printf '  %-26s -> %-38s (gate: %s, open: %s)\n' "$1" "$2" "$3" "$4" | flowline 99; }
  if [ -n "$plan" ]; then
    printed=1
    if [ -n "$planrev" ]; then st="$(review_state "$slug" "$planrev")"; trow "task/PLAN.md" "$planrev" "${st%%|*}" "${st##*|}"
    else printf '  %-26s -> %s\n' "task/PLAN.md" "(no review file yet - run: /pw-review $slug init-all)" | flowline 99; fi
  fi
  for rel in $adocs; do
    printed=1
    rvf="analysis/review/${rel#analysis/}"; rvf="${rvf%.md}.review.md"
    if [ -f "$d/$rvf" ]; then st="$(review_state "$slug" "$rvf")"; trow "$rel" "$rvf" "${st%%|*}" "${st##*|}"
    else printf '  %-26s -> %s\n' "$(printf '%s' "$rel" | cutw 25)" "(review file missing - run: /pw-review $slug init-all)" | flowline 99; fi
  done
  if [ -n "$trevs" ]; then printed=1; printf '  %-26s -> %s\n' "task/T0n.md (x$(printf '%s' "$trevs" | wc -w | tr -d ' '))" "task/review/T0n.review.md" | flowline 99; fi
  [ "$printed" = 1 ] || echo "  (nothing in analysis/ or task/ yet - start with /pw-new or /pw-adopt)"
  echo "  per-command detail with real targets: /pw-help project $slug <name>"
  stamp
}

usage() {
  cat <<'EOF'
usage: pw-help.sh <operator> [args] [--json]

  overview                    one line per command and per exposed operator
  command <name> [<slug>]     how-to manual for one command (--full = verbatim file)
  project <slug> [<name>]     what applies to THIS project right now, with real targets
  operators <name> [<op>]     verbatim usage-header dump (or one operator deep-dive)
  workflow                    the phase spine with gates
  find <term...> [--json]     literal phrase search across the tooling surface
  --selftest                  run the isolated harness case
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then usage; exit 0; fi

op0="${1:-overview}"
case "$op0" in
  overview)   shift; render_overview "$@" ;;
  command)    shift; render_command "$@" ;;
  project)    shift; render_project "$@" ;;
  operators) shift; render_operators "$@" ;;
  find)       shift; render_find "$@" ;;
  workflow)  shift; render_workflow "$@" ;;
  *)         usage >&2; die "unknown operator: $op0 → fix: bare /pw-help lists every command" ;;
esac
