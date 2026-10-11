#!/usr/bin/env bash
# ============================================================================
# pw-help.sh — deterministic discovery: one help surface for commands + operators
#
# Named-argument grammar (plan 42): operator words first, every value named; the
# project is selected with --project <slug>. Scope is DECLARED per command
# (frontmatter `scope:` + per-form `scope-forms:`) — the overview's two sections
# (Global Operations / Project Operations) and the command view's grouping read
# that declaration; nothing is inferred from shapes.
#
#   pw-help.sh overview   [--json]
#       The two scope sections: Global Operations (no existing workflow project
#       required) and Project Operations (--project <slug>; Create or Attach
#       labeled separately, then the phase buckets). One line per command form
#       AND per exposed operator of that section, each with its use case (the
#       command file's own definition line, else the script paragraph).
#       Rendered live from command frontmatter + script usage headers — zero
#       maintained snapshot. Includes pw-help.
#
#   pw-help.sh command    --name <name> [--project <slug>] [--full|--json|--maintainer]
#       The how-to manual for one command: per-operator blocks (Use when / Does /
#       doctrine labels / runnable example line) lifted from the command
#       file's own bullets + the entity's usage-header paragraphs, user-surface doc
#       pointers, and the frontmatter summary; the default human view is command surface
#       only, with --maintainer adding the entity-script sections (S1b facet-grouped
#       operator sigs) and tooling/docs pointers. With --project <slug> the invocation
#       slots show that slug. --full renders the entire command file (placeholders
#       substituted) for the rare reader that needs the doctrine verbatim.
#
#   pw-help.sh project    --project <slug> [--name <command>] [--json]
#       Project-specific how-to: current phase (read via the state reader), the
#       most-likely-next command lines filled with THIS project's real targets,
#       the review/plan/task files found on disk with gate states and open-item
#       counts, and (with --name) one command's project-scope operators
#       concretized against those targets (global forms go to a separate footer).
#       The state-rich report stays /pw-status - this view answers
#       "what do I run now, with what exact arguments".
#
#   pw-help.sh operators  --name <name> [--operator <op>]
#       Operator deep dive for the named command's entity/toolchain scripts
#       (the view the `command` footnotes point at). The name slot resolves a
#       command name, a bare name (pw- prefix added), or an entity/toolchain
#       script basename — library scripts are never listable (they are
#       source-only: L2). Without --operator: the verbatim
#       usage-header dump (S1b facet lines included). With it: just that
#       operator's usage-header paragraph,
#       one occurrence per owning script, facet-labelled.
#
#   pw-help.sh workflow   [--json]
#       The lifecycle spine: phases, their commands, and where the review
#       gates live — rendered from $PW_VALID_PHASES + the phase map, so the
#       command half can never drift.
#
#   pw-help.sh find       --term <term…> [--json] [--maintainer]
#       Bounded discovery grep across the caller-visible surfaces (tooling commands,
#       entity + toolchain script usage headers, tooling docs + root docs) — never
#       library sources, never corpus projects. The term is ONE literal
#       case-insensitive phrase (prose flag — runs until the next --flag); matches
#       print surface-grouped file:line with a trimmed snippet, capped at 20 plus a
#       how-to-narrow tail. Zero hits is a RESULT, not an error (exit 0). It is a
#       pointer, not a reader: deep content is the command view, doctrine is the
#       command file. Agents: --json returns [{surface,path,line,text}] — one cheap
#       bounded call beats exploratory greps to locate a concept across the surface set.
#
#   pw-help.sh --selftest                  run the isolated harness case.
#
# Read-only by contract: sign-off state is read through the shared mdlib latest-row
# readers (_signoff_latest_decision/_signoff_latest_actor, sourced from pw-mdlib.sh), and the
# audited subprocess whitelist stays read-only (pw-status.sh phase; pw-review-read.sh count;
# pw-config.sh get). It never runs a setter and never writes — a
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
. "$HERE/../lib/pw-mdlib.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
CMDS="$TOOL/commands"
# the READ-ONLY subprocess trio (the §3.4.1 whitelist; the T1 case pins it mechanically):
ST="$HERE/pw-status.sh"
RV="$HERE/pw-review-read.sh"
CFG="$HERE/pw-config.sh"

die() { printf "%s\n" "pw-help: $*" | flowline 98 >&2; exit 2; }

# --- the phase -> command map (embedded knowledge; the static.sh set-equality
# canary pins its names against $CMDS, so a new command cannot stay invisible) ---
HELP_PHASE_MAP="setup|pw-new pw-adopt pw-context pw-doctor;analysis|pw-research pw-analyze pw-review;breakdown|pw-breakdown pw-rfc;executing|pw-execute pw-verify pw-sync;ship|pw-ship;close|pw-close;anytime|pw-status pw-help pw-config"

# --- the Global Operations order (the overview's first section). Every command whose
# frontmatter scope is global|mixed MUST be listed here and every listed command MUST
# carry global forms; render_overview validates both directions on every run. ---
HELP_GLOBAL_ORDER="pw-help pw-doctor pw-config pw-status pw-research pw-verify"

# --- shared helpers -------------------------------------------------------------
sub() { sed -e "s|{{PW_HOME}}|$PW_HOME|g" -e "s|{{PW_PROJECTS}}|$PW_PROJECTS|g"; }
jstr() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"; printf '%s' "$s"; }
TABS="$(printf '\t')"
BT="$(printf '\140')"    # literal backtick — kept OUT of double quotes (there it starts command-sub)
TF="$(printf '\047')"    # literal single quote, same reason
US="$(printf '\037')"    # unit separator: NON-whitespace IFS for ops_detail rows — tab/newline
                         # field-splitting collapses empty fields (blank paragraph/facet), US does not.

# fmof <file> <key> — frontmatter value (same parse as gen-commands).
# Builtin line-walk: byte-identical to the former awk|sed chain (open fence at line 1,
# first "key:" row wins, leading spaces/tabs trimmed, one leading + one trailing
# single/double quote removed), zero subprocesses.
fmof() {
  local k="$2" line v nr=0
  [ -f "$1" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    nr=$((nr+1))
    if [ "$nr" = 1 ]; then
      [ "$line" = "---" ] || return 0
      continue
    fi
    [ "$line" = "---" ] && return 0
    case "$line" in
      "$k":*)
        v="${line#"$k":}"
        v="${v#"${v%%[! 	]*}"}"
        case "$v" in '"'* | "'"*) v="${v#?}" ;; esac
        case "$v" in *'"' | *"'" ) v="${v%?}" ;; esac
        printf '%s\n' "$v"
        return 0 ;;
    esac
  done < "$1"
  return 0
}

# _pwh_put <varname> <value> — bash 3.2 has no associative arrays (T0 banned anyway),
# so per-script parse caches live in indirect variables keyed by the sanitized path.
_pwh_put() { printf -v "$1" '%s' "$2"; }

# hdr_lines <script> — usage-header block (between the "# ====" rules), decommented
# with leading spaces stripped so operator signatures anchor at column 1. Memoized per
# script path: one awk parse per script per render instead of one per (script, op).
# A trailing "X" sentinel rides in the cache variable so $( ) never eats the stream's
# real trailing newlines (blank header lines are meaningful to the operators dump).
hdr_lines() {
  local key content var
  key="${1//[^a-zA-Z0-9]/_}"
  var="PWHELP_HDR_$key"
  content="${!var:-}"
  if [ -z "$content" ]; then
    content="$( { awk '/^# =+$/{c++; next} c==1 {if (/^#/) {sub(/^# ?/,""); print}} c>=2{exit}' "$1"; printf 'X'; } )"
    _pwh_put "$var" "$content"
  fi
  printf '%s' "${content%X}"
}

# ops_of <script> — operator names from "pw-<s>.sh <op>  <args>" usage-header signatures.
# <op> may be a bare word or a --flag (machine-side forms like --all have no slug slot).
# `--project` is the named project slot, never an operator: a default-flow header line
# (`pw-status.sh --project <slug> …`) contributes no operator token.
ops_of() {
  hdr_lines "$1" | awk '/^  pw-[a-z0-9-]+\.sh +(--[a-z][a-z0-9-]*|[a-z][a-z0-9-]*)([ ]|$)/ && $2 != "--project" {print $2}'
}

# ops_detail <script> — memoized "op<TAB>sig<TAB>para<TAB>facet" rows in usage-header
# signature order. One awk pass reproduces the three machines (sig_of first-line,
# para_of first-flush, facets_map+facet_of first-token) for every op at once; sig_of/
# para_of/facet_of and the overview/command hot loops then read it with builtin
# while-read loops — zero exec per op.
ops_detail() {
  local key var content
  key="${1//[^a-zA-Z0-9]/_}"
  var="PWHELP_DETAIL_$key"
  content="${!var:-}"
  if [ -z "$content" ]; then
    content="$(hdr_lines "$1" | awk '
      function tryflush() {
        if (buf == "" || txt == "") return
        n2 = split(buf, toks, SUBSEP)
        for (t = 1; t <= n2; t++) if (!(toks[t] in paras)) paras[toks[t]] = txt
      }
      /WRITE[ ]*=|READ[ ]*=|SPECIAL[ ]*=/ {
        fline = $0
        if (fline ~ /WRITE[ ]*=/) { facet = "write"; sub(/^.*WRITE[ ]*=/, "", fline) }
        else if (fline ~ /READ[ ]*=/) { facet = "read"; sub(/^.*READ[ ]*=/, "", fline) }
        else { facet = "special"; sub(/^.*SPECIAL[ ]*=/, "", fline) }
        gsub(/[,()]/, " ", fline)
        nf = split(fline, fa, /[ ]+/)
        for (fi = 1; fi <= nf; fi++) if (fa[fi] ~ /^(--)?[a-z][a-z0-9-]*$/ && !(fa[fi] in facs)) facs[fa[fi]] = facet
      }
      /^  pw-[a-z0-9-]+\.sh +(--[a-z][a-z0-9-]*|[a-z][a-z0-9-]*)([ ]|$)/ && $2 != "--project" {
        tryflush()
        o = $2
        oc++; olist[oc] = o
        if (!(o in sigs)) { s = $0; sub(/^  pw-[a-z0-9-]+\.sh +(--[a-z][a-z0-9-]*|[a-z][a-z0-9-]*)[ ]+/, "", s); sigs[o] = s }
        if (txt != "") { buf = $2; txt = "" } else buf = (buf == "" ? $2 : buf SUBSEP $2)
        next }
      NF==0 { tryflush(); buf = ""; txt = ""; next }
      { if (buf != "") { sub(/^[ ]+/, ""); txt = (txt == "" ? $0 : txt " " $0) } }
      END {
        tryflush()
        for (oi = 1; oi <= oc; oi++) { o = olist[oi]
          printf "%s\037%s\037%s\037%s\n", o, sigs[o], paras[o], facs[o] }
      }')"
    _pwh_put "$var" "$content"
  fi
  [ -n "$content" ] && printf '%s\n' "$content"
  return 0
}

# sig_of <script> <op> — argument string from the operator's usage-header signature.
sig_of() {
  local d o a p f
  d="$(ops_detail "$1")"
  while IFS="$US" read -r o a p f; do
    [ "$o" = "$2" ] || continue
    printf '%s\n' "$a"
    return 0
  done <<< "$d"
  return 0
}

# para_of <script> <op> — the operator\'s usage-header paragraph, joined to one line.
para_of() {
  local d o a p f
  d="$(ops_detail "$1")"
  while IFS="$US" read -r o a p f; do
    [ "$o" = "$2" ] || continue
    [ -n "$p" ] && printf '%s\n' "$p"
    return 0
  done <<< "$d"
  return 0
}

# gist <text> — first sentence; a period is a boundary only before space/EOL
# (so "INDEX.md's" and "pw-rfc-comments.sh)" survive).
# Builtin pattern walk: the first ". " wins (longest-suffix cut = earliest dot), else a
# trailing "."; ASCII dots/spaces cannot occur inside UTF-8 sequences, so the cut is
# byte-identical to the former per-character awk scan in every locale.
gist() {
  case "$1" in
    *". "*) printf '%s\n' "${1%%. *}"; return 0 ;;
    *".")   printf '%s\n' "${1%?}"; return 0 ;;
  esac
  printf '%s\n' "$1"
}

# facets_map <script> — "facet<TAB>op" lines from the S1b Facets block. Memoized per
# script (set-flag distinguishes "parsed, empty" from "not parsed yet").
facets_map() {
  local key var flag
  key="${1//[^a-zA-Z0-9]/_}"; var="PWHELP_FACETS_$key"; flag="PWHELP_FACETSET_$key"
  if [ -z "${!flag:-}" ]; then
    _pwh_put "$flag" 1
    _pwh_put "$var" "$(hdr_lines "$1" | awk '
      /WRITE[ ]*=|READ[ ]*=|SPECIAL[ ]*=/ {
        line=$0
        if (line ~ /WRITE[ ]*=/) { facet="write"; sub(/^.*WRITE[ ]*=/,"",line) }
        else if (line ~ /READ[ ]*=/) { facet="read"; sub(/^.*READ[ ]*=/,"",line) }
        else { facet="special"; sub(/^.*SPECIAL[ ]*=/,"",line) }
        gsub(/[,()]/," ",line)
        n=split(line, a, /[ ]+/)
        for (i=1;i<=n;i++) if (a[i] ~ /^(--)?[a-z][a-z0-9-]*$/) print facet "\t" a[i]
      }')"
  fi
  [ -n "${!var}" ] && printf '%s\n' "${!var}"
  return 0
}

# facet_of <script> <op> — write | read | special, or empty when unlabelled.
facet_of() {
  local d o a p f
  d="$(ops_detail "$1")"
  while IFS="$US" read -r o a p f; do
    [ "$o" = "$2" ] || continue
    [ -n "$f" ] && printf '%s\n' "$f"
    return 0
  done <<< "$d"
  return 0
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
#       carries a different op name (config ↔ pw-config.sh project get ai-review; item ↔ add-item).
# cmd_use_clause <cmd> <op> — the prose the command file carries for an operator's bullet
# (everything after the "—" of the mapping line), collapsed to the blurb shown in user views.
cmd_use_clause() {
  local bloc
  bloc="$(cmd_block "$1" "$2" | strip_md | sub | awk '/^[ \t]*[0-9]+[.)]/{s=1; next} s{next} { line=$0; p=index(line,"/Users/"); if (!p) p=index(line,"tooling/scripts/"); if (p) { pre=substr(line,1,p-1); gsub(/[ \t`→—-]+$/,"",pre); if (pre=="") next; print pre; next } print }')"   # stop-flag, not early {exit} (SIGPIPE under pipefail)
  printf '%s' "$bloc" | awk '{ s = s $0 " " } END {
    i = index(s, "—"); j = index(s, "→")
    if (i && (!j || i < j)) { s = substr(s, i); sub(/^—[ ]?/, "", s) }
    else if (j) { s = substr(s, j); sub(/^→[ ]?/, "", s) }
    k = index(s, "If the 2nd argument"); if (k) s = substr(s, 1, k - 1)
    gsub(/[ ]+/, " ", s); sub(/ +$/, "", s)
    sub(/[ ]*(Run|run)[ ]*:?[ ]*$/, "", s)
    do { s2 = s; sub(/[ ]+(to|of|in|is|that|and|or|the|a|an|for|with|on|at|by|as|into|through|pass|flags?|from|via)$/, "", s) } while (s != s2)
    sub(/[ :,.]+$/, "", s)
    if (s ~ /^[a-z0-9(<]/ && length(s) < 30 && s !~ /[.;:]/ && s ~ /(to|of|in|is|that|and|or|the|a|an|for|with|on|at|by|as|into|through|pass|from|via)$/) s = ""
    print s }'
}

selector_tokens() {
  printf '%s' "$1" | awk '{
    s=$0; depth=0; in1=0; seg=""; brk=""
    for (i=1; i<=length(s); i++) { c=substr(s,i,1)
      if (c=="[" || c=="<") { depth++; if (depth==1) { in1=1; brk=c; continue } }
      if (c=="]" || c==">") { if (depth==1) { if (in1 && (index(seg,"|")>0 || (brk=="[" && seg ~ /^[a-z][a-z0-9-]*$/))) found = found seg "\n"; in1=0; seg="" }; if (depth>0) depth--; continue }
      if (in1 && depth==1) seg = seg c
    }
    if (found != "") { n=split(found, G, "\n"); for (k=1; k<=n; k++) { if (G[k]=="") continue; m=split(G[k], P, "|");
        for (q=1; q<=m; q++) { t=P[q]; sub(/^[ ]+/,"",t); sub(/[ ].*$/,"",t); if (t ~ /^[a-z][a-z0-9-]*$/) print t } } }
  }' | sort
}



# has_shape <cmd> <tok> — token appears as the FIRST word after the command name in a real
# invocation span (`/pw-<cmd> <tok> …` — operator words come first in the named-argument
# grammar; the project is a --project flag, never a positional), or in a "literally `<tok>`"
# operator definition sentence. Script-form lines are NOT surface proof — C3 mapping bodies
# name internal steps.
has_shape() {
  local f="$CMDS/$1.md"
  grep -qE "/$1 $2([ ]|$BT|$TF|,|\.|\)|\$)" "$f" \
    || grep -qF -e "literally $TF$2$TF" -e "literally $BT$2$BT" -e "literally \"$2\"" "$f"
}

# user_prose — scrub maintainer-domain terms from prose that reaches the DEFAULT
# user views (overview, bare, command without --maintainer, project, workflow, find).
# The command files + script usage headers are maintained in the maintainers'
# voice; the renderers for the project/agent-facing surfaces pass every lifted
# clause through here: drop provenance/history parentheticals that name internals,
# map script names to their user-visible form, replace tooling jargon.
CMDS_LIST=":pw-new:pw-adopt:pw-context:pw-doctor:pw-research:pw-analyze:pw-review:pw-breakdown:pw-rfc:pw-execute:pw-verify:pw-sync:pw-ship:pw-close:pw-status:pw-help:pw-ship-mr-describe:pw-test:"
user_prose() {
  # BSD sed -E: no \b — guard with explicit char classes where needed. Literal parens
  # in ERE are ( ) — no backslash. Order: history parentheticals first, then jargon,
  # finally the awk pass maps any remaining pw-*.sh token to its user form.
  sed -E \
    -e 's/ \((was|moved from|renamed from|formerly|history:)[^()]*\) ?//gi' \
    -e 's/\([a-z0-9.-]+\.sh (was|from|moved|renamed)[^()]*\)//gi' \
    -e 's/read via the state reader/read from the project status/g' \
    -e 's/\(read via (the )?state reader\)/(read from the project status)/g' \
    -e 's/state reader/project status view/g' \
    -e 's/usage-header/operator-reference/g' \
    -e 's/usage headers/operator references/g' \
    -e 's/usage header/operator reference/g' \
    -e 's/entity\/toolchain scripts/internal helpers/g' \
    -e 's/entity-script sections/internal sections/g' \
    -e 's/entity \+ toolchain script operator references/internal operator references/g' \
    -e 's/commands, internal helpers references/command + helper references/g' \
    -e 's/the entity\x27s /the /g' \
    -e 's#entities#internal helpers#g' \
    -e 's#\bentity\b#internals#g' \
    -e 's#toolchain scripts#internal helpers#g' \
    -e 's#toolchain docs#internal docs#g' \
    -e 's#tooling docs#internal docs#g' \
    -e 's#tooling commands#command files#g' \
    -e 's#tooling surface#command surface#g' \
    -e 's#tooling/#internal/#g' \
    -e 's#\btooling\b#the workflow#g' \
    -e 's#script headers#operator references#g' \
    -e 's/frontmatter/command header/g' \
    -e 's/\$PW_[A-Z_]+/the bundle config/g' \
    -e 's/phase map/lifecycle map/g' \
    -e 's/pw-item-status/item-status/g' \
    -e 's/\(S1[ab][^()]*\)//g' \
    -e 's/  +/ /g' \
    -e 's/ +([,.;:!?])/\1/g' \
  | awk -v cm="$CMDS_LIST" '{
      line=$0
      while (match(line, /pw-[a-z][a-z0-9-]*\.sh/)) {
        tok=substr(line, RSTART+3, RLENGTH-6)
        pre=substr(line,1,RSTART-1); post=substr(line,RSTART+RLENGTH)
        if (index(cm, ":" tok ":")) line = pre "/pw-" tok post
        else line = pre "an internal helper" post
      }
      gsub(/  +/, " ", line); sub(/ +$/, "", line)
      print line
    }'
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


# cmd_shape_line <cmd> <tok> — the user-typed invocation args: the token as the first word
# after the command name, through the span-closing backtick/quote of the first matching
# shape line (`/pw-<cmd> <tok> --project <project-slug> …`), else empty. The first
# boundary-valid occurrence in the file wins (same first-match discipline as before).
cmd_shape_line() {
  local cmd="$1" tok="$2"
  awk -v cmd="$cmd" -v tok="$tok" -v sq="'" -v bt='`' '
    { key = "/" cmd " " tok; from = 1; pos = 0
      while (1) {
        p = index(substr($0, from), key)
        if (p == 0) break
        pos = from + p - 1
        c = substr($0, pos + length(key), 1)
        if (c == "" || c == " " || c == bt || c == sq || c == "," || c == ")" || c == ".") break
        from = pos + 1; pos = 0
      }
      if (pos == 0) next
      rest = substr($0, pos + length(key))
      sub(/^ +/, "", rest)
      i = index(rest, bt); if (i > 0) rest = substr(rest, 1, i - 1)
      j = index(rest, sq); if (j > 0) rest = substr(rest, 1, j - 1)
      sub(/ +$/, "", rest)
      if (rest == "") print tok; else print tok " " rest
      exit
    }' "$CMDS/$cmd.md" 2>/dev/null || true
  return 0
}

# token_use_clause <cmd> <tok> — the clause a "literally `<tok>`" definition line carries.
token_use_clause() {
  # the blurb = the line where "literally <tok>" appears, JOINED with its wrapped
  # continuation lines (command-file paragraphs wrap mid-sentence), then cut at the
  # first sentence terminator after the token marker.
  local n para out
  n="$(grep -m1 -nE "literally [$TF$BT]$2[$TF$BT]" "$CMDS/$1.md" | cut -d: -f1)" || return 1
  [ -n "$n" ] || return 1
  para="$(awk -v n="$n" 'NR == n { p = $0; ok = 1; next }
      ok && /^[[:space:]]*$/ { exit }
      ok && /^([-*] |[0-9]+[.)] |#|> |[|]{3})/ { exit }
      ok && (p != "") { p = p " " $0; next }
      END { print p }' "$CMDS/$1.md")"
  [ -n "$para" ] || return 1
  out="$(printf '%s' "$para" | sed -E -e "s/.*literally [$TF$BT]$2[$TF$BT][^a-zA-Z]*//" -e 's/[.,;:].*//' -e 's/^[ ]+//')"
  # If the author continues the definition after an em-dash and the pre-dash part is a
  # weak stub, keep the whole sentence; otherwise the pre-dash part is the definition.
  if [ ${#out} -ge 25 ]; then
    d="${out%%—*}"
    [ "${#d}" -ge 25 ] && out="$d"
  fi
  out="$(printf '%s' "$out" | sed -E -e 's/[ ]+—[ ]+skip everything below.*//' -e 's/[ ]+$//')"
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}
# r2_alias <cmd> <tok> — "script<TAB>op" for a sugar token: the first REAL script
# operator invoked from the token\'s bullet block (<=9 lines under the shape).
r2_alias() {
  local cmd="$1" tok="$2" ln win pair script op sp
  ln="$(grep -m1 -n -E "^[[:space:]]*-[[:space:]]+\*\*[\`]?/$cmd ${tok}([ ]|\`|\*|$)" "$CMDS/$cmd.md" 2>/dev/null | cut -d: -f1 || true)"
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
  # one awk for both width probes (awk length = BYTES in every locale — bash ${#} is
  # character-based under UTF-8 bash and would not be byte-identical here).
  if printf '%s\n%s' "$line" "$args" | awk 'NR==1{l1=length($0)} NR==2{l2=length($0)} END{exit !(l1<=98 && l2<=29)}'; then
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
  local cmd="$1" text script sp op seen="$TABS" tok ali ascript aop args use fac alias_use alias_fac alias_f first_arg_flow shape_ok d _dop a2 par
  text="$(< "$CMDS/$cmd.md")"
  case "$(fmof "$CMDS/$cmd.md" args)" in \[*|\"[\"]*) first_arg_flow=1 ;; *) first_arg_flow="" ;; esac
  # R1: real script operators whose command-form span exists.
  for script in $(own_first "$cmd" $(scripts_of "$cmd")); do
    sp="$(script_path "$script" 2>/dev/null || true)" || continue
    [ -n "$sp" ] || continue
    d="$(ops_detail "$sp")"
    for op in $(ops_of "$sp"); do
      case "$seen" in *"$TABS$op$TABS"*) continue ;; esac
      has_shape "$cmd" "$op" && : || { [ -n "$first_arg_flow" ] || continue
        case "$text" in *"/$cmd $op "*|*"/$cmd $op$BT"*) : ;; *) continue ;; esac; }
      seen="$seen$op$TABS"
      _dop=""; a2=""; par=""; fac=""
      while IFS="$US" read -r _dop a2 par fac; do
        [ "$_dop" = "$op" ] && break
      done <<< "$d"
      args="$(cmd_shape_line "$cmd" "$op")"
      if [ -z "$args" ]; then args="$op"
        [ -z "$a2" ] || args="$op $a2"
      fi
      # use text for USER surfaces comes from the command file's own bullet (after the
      # mapping) — never the script's usage paragraph (that is maintainer voice). The raw
      # script paragraph still backs the --maintainer Does section + operators deep dive.
      # order: script usage-paragraph gist (terse op sentence) -> command-file bullet
      # clause -> token sugar clause -> honest pointer. All scrubbed at the printf below.
      use="$(gist "$par")"
      [ -n "$use" ] || use="$(cmd_use_clause "$cmd" "$op")"
      [ -n "$use" ] || use="$(token_use_clause "$cmd" "$op" 2>/dev/null || true)"
      printf '%s\t%s\t%s\t%s\t%s\n' "$op" "$args" "$(printf '%s' "${use:-see: /pw-help operators --name $cmd}" | user_prose)" "$fac" "${script}"
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
    # user blurb priority for selector sugar: the definition sentence in the command
    # file; then the bullet clause; then (only via a real alias) the script paragraph.
    # The alias/facet lookup still runs for attribution (operators deep dive).
    use="$(token_use_clause "$cmd" "$tok" 2>/dev/null || true)"
    [ -n "$use" ] || use="$(cmd_use_clause "$cmd" "$tok")"
    fac=""
    if ali="$(r2_alias "$cmd" "$tok" 2>/dev/null || true)"; then
      ascript="${ali%%$TABS*}"; aop="${ali##*$TABS}"
      sp="$(script_path "$ascript" 2>/dev/null || true)"
      if [ -n "$sp" ]; then
        fac="$(facet_of "$sp" "$aop")"
        [ -n "$use" ] || use="$(gist "$(para_of "$sp" "$aop")")"
      fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$tok" "$args" "$(printf '%s' "${use:-see: /pw-help operators --name $cmd}" | user_prose)" "$fac" "${ascript:-$cmd.sh}"
  done
  return 0
}

# --- scope map (declared metadata — NEVER inferred from shapes or prose) --------------------
# Every canonical command declares `scope: global|project|mixed` in its frontmatter.
# global  — needs no existing workflow project (install checks, discovery, standalone work).
# project — selects the project with `--project <project-slug>` (creation included).
# mixed   — carries BOTH kinds of form and must classify each one in
#           `scope-forms: "tok=project, tok=global, …"` where tok is a surfaced operator
#           token, a selector flag (`--all`, `--question`, `--project`), or `default`
#           (the no-operator flow). An unclassified or unknown form is a documentation
#           defect and fails loudly — same discipline as the phase-map canary.
scope_of() {
  local cmd="$1" tok="$2" sc forms v
  sc="$(fmof "$CMDS/$cmd.md" scope)"
  case "$sc" in
    global|project) printf '%s' "$sc"; return 0 ;;
    mixed) ;;
    *) die "BUG: commands/$cmd.md scope must be global|project|mixed (got: '${sc:-missing}') → fix: add the scope: line in the same commit as the command" ;;
  esac
  forms="$(fmof "$CMDS/$cmd.md" scope-forms)"
  [ -n "$forms" ] || die "BUG: mixed command $cmd carries no scope-forms map → fix: scope-forms: \"tok=project, other=global\" in commands/$cmd.md"
  v="$(printf '%s' "$forms" | tr ',' '\n' | awk -F= -v k="$tok" '
    { key=$1; sub(/^[ \t]+/,"",key); sub(/[ \t]+$/,"",key)
      if (key==k) { val=$2; sub(/^[ \t]+/,"",val); sub(/[ \t]+$/,"",val); print val; exit } }')"
  case "$v" in
    global|project) printf '%s' "$v" ;;
    *) die "BUG: scope-forms of $cmd does not classify '$tok' → fix: add ${tok}=<global|project> to commands/$cmd.md" ;;
  esac
}

# scope_args <cmd> <global|project> — display args for one scope section. Mixed commands
# carry args-global/args-project; a single-scope command uses its one args line.
scope_args() {
  local cmd="$1" sec="$2" v
  v="$(fmof "$CMDS/$cmd.md" "args-$sec")"
  [ -n "$v" ] || v="$(fmof "$CMDS/$cmd.md" args)"
  printf '%s' "$v"
}

# has_scope_form <cmd> <global|project> — the command exposes at least one form of that scope.
has_scope_form() {
  local cmd="$1" sec="$2" sc
  sc="$(fmof "$CMDS/$cmd.md" scope)"
  case "$sc" in
    "$sec") return 0 ;;
    mixed) printf '%s' "$(fmof "$CMDS/$cmd.md" scope-forms)" | grep -q "=$sec" ; return $? ;;
  esac
  return 1
}

# has_default <cmd> — the command file carries the no-operator flow for its declared
# default scope: an invocation `/pw-<cmd> --project (<project-slug>|<slug>)` whose span
# opens an optional-arg bracket or closes right after (quote/backtick/comma/period), or
# the C1 exception (bare `/pw-help` → overview).
has_default() {
  local f="$CMDS/$1.md"
  if [ "$1" = pw-help ]; then
    grep -qF "/pw-help$BT" "$f" && return 0
    grep -qF "/pw-help$TF" "$f" && return 0
  fi
  grep -qE "/$1 --project (<project-slug>|<slug>)[ ]*([,\"'\`]|\$|\[)" "$f" && return 0
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
# Shape: two top-level scope groups — Global Operations (no existing workflow project
# required) and Project Operations (explicitly select --project <project-slug>, with
# creation/attachment labeled separately, then the phase buckets). A mixed command
# splits across the groups by its DECLARED scope-forms; each block shows only that
# scope's forms. Per command: a head line ("/pw-<cmd> <args>", use = frontmatter
# description sentence; op slot "(default)" when it has a default flow AND exposed ops),
# then one continuation line per surfaced operator with facet labels (S1b).

# ov_cmd_block <cmd> <global|project> — one overview command block for one scope section.
ov_cmd_block() {
  local cmd="$1" sec="$2" file desc args ops_lines dflt dsc sc op bargs buse bfac bscript
  file="$CMDS/$cmd.md"
  [ -f "$file" ] || die "BUG: $cmd is missing $file → fix: keep the overview groups and the commands dir in sync"
  sc="$(fmof "$file" scope)"
  desc="$(fmof "$file" description)"; args="$(scope_args "$cmd" "$sec")"
  ops_lines="$(ops_surfaced "$cmd")"
  dflt=""
  if [ -n "$ops_lines" ] && has_default "$cmd"; then
    dsc="$sc"
    if [ "$sc" = mixed ]; then
      case "$(fmof "$file" scope-forms)" in *default=*) dsc="$(scope_of "$cmd" default)" ;; *) dsc="" ;; esac
    fi
    [ -n "$dsc" ] && [ "$dsc" = "$sec" ] && dflt="(default)"
  fi
  ov_emit "/pw-${cmd#pw-}" "$dflt" "$args" "$(gist "$desc")"
  while IFS="$TABS" read -r op bargs buse bfac bscript; do
    [ -n "$op" ] || continue
    if [ "$sc" = mixed ]; then
      [ "$(scope_of "$cmd" "$op")" = "$sec" ] || continue
    elif [ "$sc" != "$sec" ]; then continue; fi
    ov_emit "" "$bfac" "$bargs" "$buse"
  done <<EOPS
$ops_lines
EOPS
  return 0
}

render_overview() {
  local json=0 a
  for a in "$@"; do
    case "$a" in
      --json) json=1 ;;
      *) die "overview: unknown option: $a → fix: /pw-help overview [--json]" ;;
    esac
  done
  local saveIFS="$IFS" ofirst=1
  local entry bucket cmd file desc args ops_lines op bargs buse bfac bscript dflt fmfacs sc jop jonsep
  # scope-declaration canary (both directions) — a new command or a stale group entry
  # fails loudly, same discipline as the phase-map set-equality canary.
  for cmd in $(cd "$CMDS" && ls *.md | sed 's/\.md$//'); do
    sc="$(fmof "$CMDS/$cmd.md" scope)"
    case "$sc" in
      global|mixed) case " $HELP_GLOBAL_ORDER " in *" $cmd "*) ;; *) die "BUG: $cmd declares scope $sc but is not in HELP_GLOBAL_ORDER → fix: add it in this script" ;; esac ;;
      project) case " $HELP_GLOBAL_ORDER " in *" $cmd "*) die "BUG: HELP_GLOBAL_ORDER names $cmd but it declares scope: project → fix: remove it in this script" ;; esac ;;
      *) die "BUG: commands/$cmd.md scope must be global|project|mixed (got '${sc:-missing}') → fix: add the scope: line in the same commit as the command" ;;
    esac
  done
  if [ "$json" = 1 ]; then
    printf '[\n'
    IFS=';'
    for entry in $HELP_PHASE_MAP; do
      IFS="$saveIFS"
      bucket="${entry%%|*}"
      for cmd in ${entry#*|}; do
        file="$CMDS/$cmd.md"
        [ -f "$file" ] || die "BUG: the phase map names $cmd but $CMDS/$cmd.md is missing → fix: update HELP_PHASE_MAP in this script in the same commit as the command"
        desc="$(fmof "$file" description)"; args="$(fmof "$file" args)"
        ops_lines="$(ops_surfaced "$cmd")"
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
        jop=""; jonsep=""
        while IFS="$TABS" read -r jon jon2 jou jou2 jon5; do
          [ -n "$jon" ] || continue
          jop="$jop$jonsep{\"name\":\"$(jstr "$jon")\",\"scope\":\"$(scope_of "$cmd" "$jon")\",\"use\":\"$(jstr "$jou")\",\"facet\":\"$(jstr "$jou2")\"}"
          jonsep=", "
        done <<EOPS
$ops_lines
EOPS

        printf '  {"cmd":"%s","args":"%s","summary":"%s","scope":"%s","agent":%s,"scripts":[%s],"facets":%s,"phase":"%s","ops":[%s]}' \
          "$jc" "$ja" "$jd" "$(fmof "$file" scope)" "$jag" "$jsc" "$jfa" "$(jstr "$bucket")" "$jop"
      done
      IFS=';'
    done
    IFS="$saveIFS"
    printf '\n]\n'
    return 0
  fi
  echo
  echo "  pw-* commands + operators - how-to per operator: /pw-help command --name <name>"
  echo "  ----------------------------------------------------------------------------"
  printf '  Global Operations - no existing workflow project required\n'
  for cmd in $HELP_GLOBAL_ORDER; do ov_cmd_block "$cmd" global; done
  echo
  printf '  Project Operations - explicitly select --project <project-slug>\n'
  printf '  Create or Attach - an existing scaffold is not required\n'
  ov_cmd_block pw-new project
  ov_cmd_block pw-adopt project
  IFS=';'
  for entry in $HELP_PHASE_MAP; do
    IFS="$saveIFS"
    bucket="${entry%%|*}"
    hits=""
    for cmd in ${entry#*|}; do
      case " pw-new pw-adopt " in *" $cmd "*) continue ;; esac
      has_scope_form "$cmd" project || continue
      hits="$hits $cmd"
    done
    [ -n "$hits" ] || continue
    echo "  $bucket"
    for cmd in $hits; do ov_cmd_block "$cmd" project; done
    IFS=';'
  done
  IFS="$saveIFS"
  stamp
}

# --- command how-to --------------------------------------------------------------------
# cmd_block <cmd> <tok> — the bullet block a command file carries for a token
# (its own shape line through the next bullet / heading), markdown included —
# the human-facing prose is lifted verbatim, never re-written.
cmd_block() {
  local cmd="$1" tok="$2" ln
  ln="$(grep -m1 -n -E "^[[:space:]]*-[[:space:]]+\*\*[\`]?/$cmd ${tok}([ ]|\`|\*|$)|^[[:space:]]*\*\*If the (1st|2nd) (word|argument) is literally [$TF$BT]${tok}[$TF$BT]" "$CMDS/$cmd.md" 2>/dev/null | cut -d: -f1 || true)"
  [ -n "$ln" ] || return 0
  awk -v from="$ln" 'NR<from{next} NR>from && (/^- \*\*/ || /^## / || /^[0-9]+\. \*\*/){exit} NR>=from{print}' "$CMDS/$cmd.md"
}

strip_md() { sed -e 's/\*\*//g' -e 's/\*//g' -e 's/`//g' -e 's/^[ >-]\{1,3\}//' -e 's/^[[:space:]]*//'; }

# scope_tokens <cmd> <global|project> — comma-joined form tokens of that scope from the
# scope-forms map (display only; scope_of stays the single classification authority).
scope_tokens() {
  printf '%s' "$(fmof "$CMDS/$1.md" scope-forms)" | tr ',' '\n' | awk -F= -v s="$2" '
    { k=$1; sub(/^[ \t]+/,"",k); sub(/[ \t]+$/,"",k); v=$2; sub(/^[ \t]+/,"",v); sub(/[ \t]+$/,"",v)
      if (v==s && k!="") { out=out sep k; sep=", " } } END { printf "%s", out }'
}

render_command() {
  local name="" slug="" a full=0 json=0 mant=0
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --name) [ $# -ge 1 ] || die "command: --name needs a value → fix: /pw-help command --name <name> [--project <slug>]"; name="$1"; shift ;;
      --name=*) name="${a#*=}" ;;
      --project) [ $# -ge 1 ] || die "command: --project needs a value → fix: /pw-help command --name <name> [--project <slug>]"; slug="$1"; shift ;;
      --project=*) slug="${a#*=}" ;;
      --full) full=1 ;;
      --json) json=1 ;;
      --maintainer) mant=1 ;;
      -*) die "command: unknown option: $a → fix: /pw-help command --name <name> [--project <slug>] [--full|--json|--maintainer]" ;;
      *) _pw_positional "$a" "operator words first, values named → /pw-help command --name <name> [--project <slug>]" ;;
    esac
  done
  [ -n "$name" ] || die "command: --name is required → fix: /pw-help command --name <name> [--project <slug>]"
  local c; c="$(canon "$name")"
  local file="$CMDS/$c.md"
  [ -f "$file" ] || die "no such command: $(canon "$name") → fix: $(did_you_mean "$c")"
  local desc args agn sc
  desc="$(fmof "$file" description)"; args="$(fmof "$file" args)"; agn="$(fmof "$file" agent)"
  sc="$(fmof "$file" scope)"
  case "$sc" in global|project|mixed) ;; *) die "BUG: commands/$c.md scope must be global|project|mixed (got '${sc:-missing}') → fix: add the scope: line" ;; esac

  if [ "$full" = 1 ]; then
    awk 'c==2{print} $0=="---"{c++}' "$file" | sub
    return 0
  fi

  local ops_lines; ops_lines="$(ops_surfaced "$c")"
  if [ "$json" = 1 ]; then
    local o_name o_args o_use o_fac o_scr bloc jops="" sep=""
    while IFS="$TABS" read -r o_name o_args o_use o_fac o_scr; do
      [ -n "$o_name" ] || continue
      jops="$jops$sep{\"name\":\"$(jstr "$o_name")\",\"scope\":\"$(scope_of "$c" "$o_name")\",\"args\":\"$(jstr "$o_args")\",\"use\":\"$(jstr "$o_use")\",\"facet\":\"$(jstr "$o_fac")\"}"
      sep=", "
    done <<E
$ops_lines
E
    printf '{"cmd":"%s","args":"%s","summary":"%s","scope":"%s","agent":%s,"ops":[%s],"scripts":[%s]}
' \
      "$(jstr "$c")" "$(jstr "$args")" "$(jstr "$desc")" "$(jstr "$sc")" \
      "$( [ -n "$agn" ] && printf '"%s"' "$(jstr "$agn")" || printf 'null' )" \
      "$jops" "$(scripts_of "$c" | sed 's/.*/"&"/' | paste -sd, - )"
    return 0
  fi

  local sl="${slug:-<project-slug>}"
  { printf '/pw-%s - %s\n' "${c#pw-}" "$desc"; } | flowline 98
  { printf 'args: %s\n' "$args"; } | flowline 98
  [ -n "$agn" ] && { printf 'agent lane: %s\n' "$agn"; } | flowline 98
  [ -n "$slug" ] && { printf 'project: %s\n' "$slug"; } | flowline 98
  if [ "$sc" = mixed ]; then
    { printf 'scope: mixed (global forms: %s | project forms: %s)\n' "$(scope_tokens "$c" global)" "$(scope_tokens "$c" project)"; } | flowline 98
  else
    { printf 'scope: %s\n' "$sc"; } | flowline 98
  fi
  echo
  # (default) flow line — the no-operator invocation with the project substituted. On a
  # mixed command it renders INSIDE its declared scope group (never floating between the
  # two); on a single-scope command it prints before the operator list.
  local mixed=0; [ "$sc" = mixed ] && mixed=1
  local default_line="" dflt_use="" dsc=""
  if has_default "$c"; then
    dsc="$sc"
    if [ "$sc" = mixed ]; then
      case "$(fmof "$file" scope-forms)" in *default=*) dsc="$(scope_of "$c" default)" ;; *) dsc="" ;; esac
    fi
    if [ "$c" = pw-help ]; then
      default_line="  (default)  /pw-help"
    elif [ -n "$dsc" ]; then
      default_line="$(printf '  (default)  /pw-%s --project %s' "${c#pw-}" "$sl")"
    fi
    [ -n "$default_line" ] && dflt_use="    Use:     the no-operator default flow - see the args line above"
  fi
  local default_done=0
  if [ -n "$default_line" ] && [ "$mixed" = 0 ]; then
    printf '%s\n' "$default_line" | flowline 98
    printf '%s\n' "$dflt_use"
    default_done=1
  fi
  local bname bargs buse bfac bscript sp2 par usep
  # Scope split (plan 42): the command's DECLARED scope-forms classify every operator;
  # mixed commands render both groups under the same two labels the overview uses —
  # never a flat same-tier list, never shape inference. Global forms group first,
  # mirroring the overview's section order.
  local mixed_gl="" mixed_pj="" _l _n2
  if [ "$mixed" = 1 ]; then
    while IFS= read -r _l; do
      [ -n "$_l" ] || continue
      _n2="${_l%%"$TABS"*}"
      if [ "$(scope_of "$c" "$_n2")" = global ]; then mixed_gl="$mixed_gl$_l
"; else mixed_pj="$mixed_pj$_l
"; fi
    done <<EOSPLIT
$ops_lines
EOSPLIT
    ops_lines="${mixed_gl}${mixed_pj}"
  fi
  local prev_sc="" bsc
  while IFS="$TABS" read -r bname bargs buse bfac bscript; do
    [ -n "$bname" ] || continue
    bsc="$(scope_of "$c" "$bname")"
    if [ "$mixed" = 1 ] && [ -n "$bsc" ] && [ "$bsc" != "$prev_sc" ]; then
      if [ "$bsc" = global ]; then
        printf '\n  Global Operations - no existing workflow project required:\n'
      else
        printf '\n  Project Operations - select --project <project-slug>:\n'
      fi
      if [ "$default_done" = 0 ] && [ -n "$default_line" ] && [ "$bsc" = "$dsc" ]; then
        printf '%s\n' "$default_line" | flowline 98
        printf '%s\n' "$dflt_use"
        default_done=1
      fi
      prev_sc="$bsc"
    fi
    printf '  %s  %s\n' "$(printf '%-11s' "$bname")" "${bargs#$bname }" | flowline 98
    # The command file's OWN bullet prose = use-when behavior; the script paragraph = Does.
    local bloc
    bloc="$(cmd_block "$c" "$bname" | strip_md | sub | awk '/^[ \t]*[0-9]+[.)]/{s=1; next} s{next} { line=$0; p=index(line,"/Users/"); if (!p) p=index(line,"tooling/scripts/"); if (p) { pre=substr(line,1,p-1); gsub(/[ \t\-`→—]+$/,"",pre); if (pre=="") next; print pre; next } print }')"   # stop-flag, NOT {exit}: an early exit SIGPIPEs the producing chain under pipefail (rc 141)
    # the human prose = block text after the first em-dash (the mapping arrow prefix
    # ends in "—"); joined, collapsed.
    usep="$(printf '%s' "$bloc" | awk '{ s=s $0 " " } END { i=index(s,"—"); j2=index(s,"→"); if (i) { s=substr(s,i); sub(/^—[ ]?/,"",s) } else if (j2) { s=substr(s,j2); sub(/^→[ ]?/,"",s) }; j=index(s,"If the 2nd argument"); if (j) s=substr(s,1,j-1); gsub(/[ ]+/," ",s); sub(/ +$/,"",s); sub(/[ ]*(Run|run)[ ]*:?[ ]*$/,"",s); do { s2=s; sub(/[ ]+(to|of|in|is|that|and|or|the|a|an|for|with|on|at|by|as|into|through|pass|flags?|from|via)$/,"",s) } while (s!=s2); sub(/[ :,.]+$/,"",s); if (s ~ /^[a-z0-9(<]/ && length(s) < 30 && s !~ /[.;:]/ && s ~ /(to|of|in|is|that|and|or|the|a|an|for|with|on|at|by|as|into|through|pass|fl|from|via)$/) s=""; print s }')"
    sp2="$(script_path "$bscript" 2>/dev/null || true)"
    par=""; [ -n "$sp2" ] && par="$(para_of "$sp2" "$bname")"
    # USER view: the same source ops_surfaced picked (definition/bullet/script-paragraph,
    # scrubbed) so overview and command views never disagree. Maintainer view shows the
    # raw bullet clause and the raw script paragraph in addition.
    [ -n "$buse" ] || buse="$usep"
    if [ "$mant" = 1 ]; then
      [ -n "$usep" ] && printf '%s\n' "$usep" | ov_wrap "    Use when: " "             + "
      { printf '%s\n' "$par"; } | ov_wrap "    Does (script): " "             + "
    fi
    printf '%s\n' "$buse" | user_prose | ov_wrap "    Does:   " "             + "
    printf '%s\n' "$bloc" | awk '/DOCTRINE|HUMAN-TRIGGERED ONLY/{print "    " $0}' | head -2 | flowline 98 || true
    { printf '%s\n' "$bloc" | grep -oE 'A[12] [a-zA-Z][^`)”]*' | head -1 | sed 's/^/    Shape:  /' | flowline 98; } || true
    # the runnable example: operator words first, args already carry the named grammar —
    # substitute the real project when one was given on the command line.
    local ex
    ex="/pw-${c#pw-} $bargs"
    ex="${ex//<project-slug>/$sl}"
    ex="${ex//<slug>/$sl}"
    printf '    $ %s\n' "$ex" | sed -e 's/[ ]*$//' | flowline 98
  done <<E
$ops_lines
E
  # a mixed command's declared default scope may have no surfaced operator to open its
  # group — render that group + the default line so the default form is never invisible.
  if [ -n "$default_line" ] && [ "$default_done" = 0 ]; then
    if [ "$mixed" = 1 ]; then
      if [ "$dsc" = global ]; then
        printf '\n  Global Operations - no existing workflow project required:\n'
      else
        printf '\n  Project Operations - select --project <project-slug>:\n'
      fi
    fi
    printf '%s\n' "$default_line" | flowline 98
    printf '%s\n' "$dflt_use"
  fi
  if [ -n "$ops_lines" ]; then
    :
  elif [ "$mixed" = 1 ]; then
    # flag-selector mixed commands (pw-doctor, pw-research): the FORMS are the args lines,
    # so render one runnable example per declared scope section.
    local fargs
    if has_scope_form "$c" global; then
      printf '\n  Global Operations - no existing workflow project required:\n'
      fargs="$(scope_args "$c" global)"; fargs="${fargs//<project-slug>/$sl}"; fargs="${fargs//<slug>/$sl}"
      printf '    $ /pw-%s %s\n' "${c#pw-}" "$fargs" | flowline 98
    fi
    if has_scope_form "$c" project; then
      printf '\n  Project Operations - select --project <project-slug>:\n'
      fargs="$(scope_args "$c" project)"; fargs="${fargs//<project-slug>/$sl}"; fargs="${fargs//<slug>/$sl}"
      printf '    $ /pw-%s %s\n' "${c#pw-}" "$fargs" | flowline 98
    fi
  else
    printf '  (single flow - no operator dispatch on this command)\n'
  fi
  echo
  local script sp nops
  if [ "$mant" = 1 ]; then
  for script in $(own_first "$c" $(scripts_of "$c")); do
    sp="$(script_path "$script" 2>/dev/null || true)"; [ -n "$sp" ] || continue
    nops="$(ops_of "$sp" | wc -l | tr -d ' ')"
    printf 'entity script: %s (%s operators - read all: /pw-help operators --name %s)\n' "${sp#$PW_HOME/}" "$nops" "${script%.sh}" | flowline 98
    while IFS= read -r o; do
      [ -n "$o" ] || continue
      f="$(facet_of "$sp" "$o")"
      printf '    %-8s %-26s %s\n' "$f" "$o" "$(sig_of "$sp" "$o")" | flowline 98
    done <<EO
$(ops_of "$sp")
EO
  done
  fi
  [ "$mant" = 1 ] || { printf '  (user view - detail: command --name %s --maintainer, or operators --name %s)\n' "$c" "$c" | flowline 98; }
  local dpaths dpl
  dpaths="$(grep -oE '(tooling/)?docs/[A-Za-z0-9._/-]+\.md' "$file" | sort -u || true)"
  while IFS= read -r dpl; do
    [ -n "$dpl" ] || continue
    if [ "$mant" != 1 ]; then case "$dpl" in tooling/*) continue ;; esac; fi
    printf 'doc: %s\n' "$dpl"
  done <<EDOC
$dpaths
EDOC
  # doctrine echo (C3): a pure mechanical command renders the single-judgment-point line; a
  # mixed command (mechanical row operators + a reasoning operator that loads a skill reference)
  # renders the split so help never calls the whole command mechanical — prepare is the
  # reasoning operator (/pw-context), pinned by the command file's own wording.
  if grep -qF 'mechanical mapping (C3)' "$file"; then
    if grep -qF 'reasoning operator' "$file"; then
      echo "doctrine: operator split - req-init/add-input/add-repo are mechanical mappings (C3) run verbatim; prepare is a reasoning operator (loads the context reference, stops before analysis)." | flowline 98
    else
      echo "doctrine: mechanical mapping (C3) - the script is the single judgment point." | flowline 98
    fi
  fi
  stamp
}

# --- operators (deep dump) --------------------------------------------------------------
render_operators() {
  local name="" op="" a c sp scripts="" s found="" facet
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --name) [ $# -ge 1 ] || die "operators: --name needs a value → fix: /pw-help operators --name <name> [--operator <op>]"; name="$1"; shift ;;
      --name=*) name="${a#*=}" ;;
      --operator) [ $# -ge 1 ] || die "operators: --operator needs a value → fix: /pw-help operators --name <name> [--operator <op>]"; op="$1"; shift ;;
      --operator=*) op="${a#*=}" ;;
      -h|--help) usage; exit 0 ;;
      -*) die "operators: unknown option: $a → fix: /pw-help operators --name <name> [--operator <op>]" ;;
      *) _pw_positional "$a" "operator words first, values named → /pw-help operators --name <name> [--operator <op>]" ;;
    esac
  done
  [ -n "$name" ] || die "operators: --name is required → fix: /pw-help operators --name <name> [--operator <op>]"
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
  # agent-lane commands have no scripts; the how-to lives in the command view.
  [ -n "$scripts" ] || die "$c is an agent-lane command - no entity/toolchain scripts -> fix: /pw-help command --name $c"
  if [ -n "$op" ]; then
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      printf '%s\n' "$(ops_of "$s")" | grep -qx "$op" || continue
      found="yes"
      printf '%s :: %s %s\n' "$(basename "$s")" "$op" "$(sig_of "$s" "$op")" | flowline 98
      para_of "$s" "$op" | fold -s -w 92 | sed 's/^/    /'
      facet="$(facet_of "$s" "$op")"
      [ -n "$facet" ] && printf '    (facet: %s)\n' "$facet"
    done <<E
$scripts
E
    [ -n "$found" ] || die "no such operator \"$op\" in $c → fix: /pw-help operators --name $c lists all operators"
  else
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      echo "== $(basename "$s") =="
      hdr_lines "$s" | sub | flowline 98
      echo
    done <<E
$scripts
E
  fi
  stamp
}

# --- workflow ---------------------------------------------------------------------------
render_workflow() {
  local json=0 a
  for a in "$@"; do
    case "$a" in
      --json) json=1 ;;
      *) die "workflow: unknown option: $a → fix: /pw-help workflow [--json]" ;;
    esac
  done
  local phase line gate first=1
  [ "$json" = 1 ] && printf '{"phases":['
  for phase in $PW_VALID_PHASES; do
    case "$phase" in
      context)   line="/pw-new --project <slug> · /pw-adopt --project <slug> · /pw-context prepare --project <slug> [--brief <prose…>] (or fill context/ + add-input rows)" ; gate="" ;;
      analysis)  line="/pw-research (optional) · /pw-analyze --project <slug>" ; gate="analysis/review/<topic>.review.md sign-off" ;;
      breakdown) line="/pw-breakdown --project <slug>" ; gate="THE hard gate: task/review/PLAN.review.md (+ per-task reviews)" ;;
      executing) line="/pw-execute --project <slug> · /pw-verify (any target) · /pw-sync --project <slug>" ; gate="worktree sub-agents, verified commits" ;;
      review)    line="/pw-ship --project <slug> · comment loop back through /pw-review · re-sync when the base moves" ; gate="MR open + comments folded into the review docs" ;;
      done)      line="/pw-close --project <slug>" ; gate="teardown, learnings, Status: done" ;;
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
    echo "any-time    /pw-status (project or --all) · /pw-help · /pw-doctor"
    stamp
  fi
}


# --- find -------------------------------------------------------------------------------
find_surfaces() { # "<label>\t<root>" sources. Default (USER) domain: the command files +
  # the root docs. Maintainer domain (-maintainer): entity/toolchain usage headers +
  # tooling/docs. L2 libraries are never searched.
  printf 'command\t%s/commands\n' "$TOOL"
  printf 'doc\t%s/../docs\n' "$TOOL"
  [ "${1:-user}" = maint ] || return 0
  printf 'script\t%s/scripts/entities\n' "$TOOL"
  printf 'script\t%s/scripts/toolchain\n' "$TOOL"
  printf 'tooling-doc\t%s/docs\n' "$TOOL"
}

render_find() {
  local json=0 mant=0 phrase="" a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --term=*) v="${a#*=}"; a="--term" ;; esac
    case "$a" in
      --term)
        while [ $# -gt 0 ]; do case "$1" in --*) break ;; esac; v="${v:+$v }$1"; shift; done
        [ -n "$v" ] || die "find: --term requires a value → fix: /pw-help find --term <term…> (one literal phrase)"
        phrase="${phrase:+$phrase }$v" ;;
      --json) json=1 ;;
      --maintainer) mant=1 ;;
      -h|--help) usage; exit 0 ;;
      -*) die "find: unknown option: $a → fix: /pw-help find --term <term…> [--json] [--maintainer]" ;;
      *) _pw_positional "$a" "the search term is named → /pw-help find --term <term…>" ;;
    esac
  done
  [ -n "$phrase" ] || die "find: no search term → fix: /pw-help find --term <term…> (one literal phrase)"
  local label root hits
  hits="$(mktemp)"
  while IFS="$TABS" read -r label root; do
    [ -d "$root" ] || continue
    grep -rinF --include='*.sh' --include='*.md' -- "$phrase" "$root" 2>/dev/null \
      | sed -e "s|^|${label}@@|" >> "$hits" || true
  done <<EF
$(find_surfaces "$([ "$mant" = 1 ] && echo maint || echo user)")
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
    out.append((surf, path, ln, " ".join(text.split())))
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
    [ "$mant" = 1 ] || echo "  - this default search covers the command files + docs (for maintainers: add --maintainer to search the operator references, tooling docs, and script headers too)"
  else
    while IFS="$TABS" read -r surf pth ln txt; do
      n=$((n+1)); [ "$n" -le 20 ] || break
      [ "$mant" = 1 ] || pth="${pth#tooling/}"
      printf '  %-12s %s:%s  %s\n' "$surf" "$pth" "$ln" "$txt" | flowline 98
    done < "$norm"
    [ "$n" -le 20 ] || printf '  (%s more - narrow the phrase, or the how-to view: /pw-help command --name <name>)\n' "$((total-20))"
  fi
  rm -f "$hits" "$norm"
  stamp
}

# --- usage / dispatch ------------------------------------------------------------------------

# --- project-specific view ------------------------------------------------------------------
# proj_dir mirrors the sibling entities' helper (die text in pw-help voice, full names).
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "project not found under $PROJECTS_DIR/$1 -> fix: scaffold it with /pw-new --project $1, or check /pw-status --project $1"; printf '%s' "$d"; }

# review_state <slug> <rel> — "<decision>|<actor>|<open-count>" via the read operators only.
# Decision and actor come from the shared mdlib latest-ROW readers: the Sign-off table's
# CURRENT cells verbatim — never a historical whole-file "approved" grep, and never the
# phase-token parser (whose hyphen split truncated "changes-requested" to "changes" and
# rendered every hyphenated decision as "pending"). Richer By values
# ("pw-reviewer (auto; provider=<p>; model=<m>)") display as the actor WITHOUT altering the
# decision token; a placeholder row yields an empty actor (blank = first use, not a person).
review_state() {
  local slug="$1" rel="$2" f dec actor="" cnt
  f="$PROJECTS_DIR/$slug/$rel"
  dec="$(_signoff_latest_decision "$f" 2>/dev/null)" || dec=""
  actor="$(_signoff_latest_actor "$f" 2>/dev/null)" || actor=""
  [ -n "$dec" ] || dec="none yet"
  cnt="$(PW_PROJECTS_DIR="$PROJECTS_DIR" "$RV" count --project "$slug" --file "$rel" 2>/dev/null)" || cnt="open=?"
  printf '%s|%s|%s' "$dec" "$actor" "$(printf '%s' "$cnt" | sed -e 's/^open=//' -e 's/ resolved=[0-9]*//' -e 's/ items=[0-9]*//')"
}

# split_state <triple> — "<decision>|<actor>|<open>" into RS_DEC/RS_ACT/RS_OPEN.
# Table cells cannot contain "|", so positional splits are exact.
split_state() {
  RS_DEC="${1%%|*}"
  RS_ACT="$(printf '%s' "$1" | cut -d'|' -f2)"
  RS_OPEN="$(printf '%s' "$1" | cut -d'|' -f3)"
}

# review_line <rel> <triple> — one aligned gates display row: current decision, its actor
# when non-blank, live open count. Values are row DATA, never script names — the view stays
# script-free.
review_line() {
  split_state "$2"
  if [ -n "$RS_ACT" ]; then
    printf '    %-42s decision: %-19s open: %s · by: %s\n' "$1" "$RS_DEC" "$RS_OPEN" "$RS_ACT" | flowline 98
  else
    printf '    %-42s decision: %-19s open: %s\n' "$1" "$RS_DEC" "$RS_OPEN"
  fi
}

# render_project_next <slug> <phase> <plan> <planrev> <dir> <plain|json>
render_project_next() {
  local slug="$1" phase="$2" plan="$3" planrev="$4" mode="$6"
  local lines l first=1 a
  case "$phase" in
    context)
      lines="/pw-context prepare --project $slug                    assisted: draft the brief + register inputs/repos from what you say
/pw-context req-init --project $slug                           manual: create the brief, fill it, then register rows with add-input/add-repo
/pw-analyze --project $slug                                    create analysis/<topic>.md (+ its review sibling)" ;;
    analysis)
      lines="/pw-review --project $slug                                    item/answer/sign-off your analysis reviews (targets above)
/pw-breakdown --project $slug                                  approved analysis -> task/PLAN.md + T0n files" ;;
    breakdown)
      if [ -z "$plan" ]; then
        lines="/pw-breakdown --project $slug                            no task/PLAN.md yet: get the analysis gates approved first (see targets + fix hints)"
      elif [ -z "$planrev" ]; then
        lines="/pw-review init-all --project $slug                        review file for PLAN.md missing - create it first
       (then: item / answer / signoff on task/review/PLAN.review.md, then /pw-execute --project $slug)"
      else
        lines="/pw-review item --project $slug --file $planrev --section §2 --text <your ask>   file a review item (auto Rn)
/pw-review signoff --project $slug --file $planrev --decision <your decision>   HUMAN-TRIGGERED ONLY (C4)
       (decision is one of: approved | changes-requested | in-review)
/pw-execute --project $slug                                    after the plan gate approves"
      fi ;;
    executing)
      lines="/pw-verify --task T0n                                     independent check of ONE change
/pw-sync --project $slug                                     merge when the base branch moved
/pw-ship --project $slug                                     push verified task branches + open MRs" ;;
    review)
      lines="/pw-review --project $slug                                    apply comments folded back from the MR
/pw-ship comments --project $slug                            pull new MR comments in
/pw-sync --project $slug                                     re-sync when the base moves" ;;
    done)
      lines="/pw-close --project $slug                                      teardown, learnings, Status: done" ;;
    *)
      lines="/pw-status --project $slug                                    (phase token unparseable - check the README.md Status: line)" ;;
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
    for rel in $planrev; do st="$(review_state "$slug" "$rel")"; review_line "$rel" "$st"; done
    for rel in $adocs; do
      rvf="analysis/review/${rel#analysis/}"; rvf="${rvf%.md}.review.md"
      [ -f "$d/$rvf" ] && { st="$(review_state "$slug" "$rvf")"; review_line "$rvf" "$st"; } || true
    done
    [ -n "$planrev$adocs" ] || echo "    (no review files yet - run: /pw-review init-all --project $slug)"
    echo "  items:"
    local revlist="$planrev" arel shown=0
    for arel in $adocs; do rvf="analysis/review/${arel#analysis/}"; rvf="${rvf%.md}.review.md"; [ -f "$d/$rvf" ] && revlist="$revlist $rvf" || true; done
    [ -n "$trevs" ] && revlist="$revlist $trevs"
    for rvf in $revlist; do
      [ -f "$d/$rvf" ] || continue
      _ishown="$(grep -oE '^### (Q|R)[0-9]+.*\[(PENDING|OPEN)\]' "$d/$rvf" 2>/dev/null | awk 'NR<=3' | cut -c5- | sed "s|^|      $rvf  |" | flowline 96)"
      [ -n "$_ishown" ] && { printf '%s\n' "$_ishown"; shown=1; }   # capture-then-print: a trailing `grep -q .` would SIGPIPE flowline under pipefail
    done
    [ "$shown" = 1 ] || echo "      (no open items / pending questions in the review files found)"
    echo "  runnable:"
    printf '    /pw-review item --project %s --file %s --section §3 --text <your ask>\n' "$slug" "${planrev:-task/review/PLAN.review.md}"
    printf '    /pw-review signoff --project %s --file %s --decision <your decision>   HUMAN-TRIGGERED ONLY (C4)\n' "$slug" "${planrev:-task/review/PLAN.review.md}"
    printf '           (decision is one of: approved | changes-requested | in-review)\n'
    local cfgs
    cfgs="$(PW_PROJECTS_DIR="$PROJECTS_DIR" "$CFG" get --project "$slug" --key ai-review 2>/dev/null | tr '\n' ' ')"
    [ -n "$cfgs" ] || cfgs="-"
    printf '    /pw-review ai --project %s --surface <analysis|plan|task-plan|task-exec|ship|rfc|close>   second opinion (modes: %s)\n' "$slug" "$cfgs" | flowline 98
    printf '    /pw-config set --project %s --key ai-review --set <surface>=<advisory|auto>   (legacy off reads as advisory; scheduling: --key review-trigger)\n' "$slug" | flowline 98
    stamp; return 0
  fi
  echo "/pw-${c#pw-} for $slug (phase: $phase)"
  local op args2 use2 fac2 s5 psc shown_cmd=0
  while IFS="$TABS" read -r op args2 use2 fac2 s5; do
    [ -n "$op" ] || continue
    psc="$(scope_of "$c" "$op")"
    [ "$psc" = project ] || continue
    args2="${args2//<project-slug>/$slug}"
    args2="${args2//<slug>/$slug}"
    printf '    /pw-%s %s\n' "${c#pw-}" "$args2"
    shown_cmd=1
  done <<EPCC
$(ops_surfaced "$c")
EPCC
  [ "$shown_cmd" = 1 ] || printf '    (no project-scoped operators on this command; see: /pw-help command --name %s)\n' "$c"
  local gtok gstr
  gtok="$(scope_tokens "$c" global)"
  if [ -n "$gtok" ]; then
    gstr="$(printf '%s' "$gtok" | sed 's/, / · /g')"
    printf '    global forms (no project): %s   detail: /pw-help command --name %s\n' "$gstr" "$c" | flowline 98
  fi
  stamp
}

render_project() {
  local slug="" name="" json=0 a
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --project) [ $# -ge 1 ] || die "project: --project needs a value → fix: /pw-help project --project <slug> [--name <command>]"; slug="$1"; shift ;;
      --project=*) slug="${a#*=}" ;;
      --name) [ $# -ge 1 ] || die "project: --name needs a value → fix: /pw-help project --project <slug> [--name <command>]"; name="$1"; shift ;;
      --name=*) name="${a#*=}" ;;
      --json) json=1 ;;
      -h|--help) usage; exit 0 ;;
      -*) die "project: unknown option: $a → fix: /pw-help project --project <slug> [--name <command>] [--json]" ;;
      *) _pw_positional "$a" "the project is named → /pw-help project --project <slug> [--name <command>]" ;;
    esac
  done
  [ -n "$slug" ] || die "project: --project is required → fix: /pw-help project --project <slug> [--name <command>]"
  local d; d="$(proj_dir "$slug")"
  local raw tok
  raw="$(PW_PROJECTS_DIR="$PROJECTS_DIR" "$ST" phase --project "$slug" 2>/dev/null)" || raw="?"
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
    for rel in $planrev; do st="$(review_state "$slug" "$rel")"; split_state "$st"; printf '%s{"doc":"task/PLAN.md","review":"%s","gate":"%s","actor":"%s","open":"%s"}' "$sep" "$(jstr "$rel")" "$(jstr "$RS_DEC")" "$(jstr "$RS_ACT")" "$(jstr "$RS_OPEN")"; sep=", "; done
    for rel in $adocs; do
      rvf="analysis/review/${rel#analysis/}"; rvf="${rvf%.md}.review.md"
      if [ -f "$d/$rvf" ]; then st="$(review_state "$slug" "$rvf")"; split_state "$st"; printf '%s{"doc":"%s","review":"%s","gate":"%s","actor":"%s","open":"%s"}' "$sep" "$(jstr "$rel")" "$(jstr "$rvf")" "$(jstr "$RS_DEC")" "$(jstr "$RS_ACT")" "$(jstr "$RS_OPEN")"; sep=", "; fi
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
  echo "  /pw-status --project $slug  ·  /pw-context prepare --project $slug (or add-input/add-repo rows)"
  echo "targets found on disk:"
  local trow printed=0
  trow() { split_state "$3"
    if [ -n "$RS_ACT" ]; then
      printf '  %-26s -> %-38s (gate: %s, open: %s, by: %s)\n' "$1" "$2" "$RS_DEC" "$RS_OPEN" "$RS_ACT" | flowline 99
    else
      printf '  %-26s -> %-38s (gate: %s, open: %s)\n' "$1" "$2" "$RS_DEC" "$RS_OPEN" | flowline 99
    fi
  }
  if [ -n "$plan" ]; then
    printed=1
    if [ -n "$planrev" ]; then st="$(review_state "$slug" "$planrev")"; trow "task/PLAN.md" "$planrev" "$st"
    else printf '  %-26s -> %s\n' "task/PLAN.md" "(no review file yet - run: /pw-review init-all --project $slug)" | flowline 99; fi
  fi
  for rel in $adocs; do
    printed=1
    rvf="analysis/review/${rel#analysis/}"; rvf="${rvf%.md}.review.md"
    if [ -f "$d/$rvf" ]; then st="$(review_state "$slug" "$rvf")"; trow "$rel" "$rvf" "$st"
    else { printf '  %s -> %s\n' "$rel" "(review file missing - run: /pw-review init-all --project $slug)"; } | flowline 99; fi
  done
  if [ -n "$trevs" ]; then printed=1; printf '  %-26s -> %s\n' "task/T0n.md (x$(printf '%s' "$trevs" | wc -w | tr -d ' '))" "task/review/T0n.review.md" | flowline 99; fi
  [ "$printed" = 1 ] || echo "  (nothing in analysis/ or task/ yet - start with /pw-new or /pw-adopt)"
  echo "  per-command detail with real targets: /pw-help project --project $slug --name <command>"
  stamp
}

usage() {
  cat <<'EOF'
usage: pw-help.sh [<operator>] [flags]

  overview [--json]                      one line per command and per exposed operator,
                                         grouped as Global vs Project operations
  command --name <name> [--project <project-slug>] [--full|--json|--maintainer]
                                         how-to manual for one command (--full = verbatim file)
  project --project <project-slug> [--name <command>] [--json]
                                         what applies to THIS project right now, real targets
  operators --name <name> [--operator <op>]
                                         verbatim usage-header dump (or one-operator deep dive)
  workflow [--json]                      the phase spine with gates
  find --term <term…> [--json] [--maintainer]
                                         literal phrase search across the tooling surface
  --selftest                             run the isolated harness case

Grammar: operator words first, every value named (--project selects the project);
unknown flags and stray positionals fail closed. The bare /pw-help shows the overview.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then usage; exit 0; fi

op0="${1:-overview}"
case "$op0" in
  -*) op0=overview ;;   # a leading flag keeps the default overview (e.g. bare /pw-help --json)
  *) (( $# > 0 )) && shift || true ;;   # bare /pw-help: $#=0 must not trip set -e on shift
esac
case "$op0" in
  overview)   render_overview "$@" ;;
  command)    render_command "$@" ;;
  project)    render_project "$@" ;;
  operators)  render_operators "$@" ;;
  find)       render_find "$@" ;;
  workflow)   render_workflow "$@" ;;
  *)          usage >&2; die "unknown operator: $op0 → fix: /pw-help (bare, shows the overview)" ;;
esac
