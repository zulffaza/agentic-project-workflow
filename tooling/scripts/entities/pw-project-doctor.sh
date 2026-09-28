#!/usr/bin/env bash
# ============================================================================
# pw-project-doctor.sh — the PROJECT side of pw-doctor (the global side checks
# the install; this checks that ONE project is operated well and still matches
# the current global config). One diagnostic walk of the project's own phases:
# every check prints ✓ / ✗ / · (· = informational, never fails) plus a fix
# hint on ✗; summary line greppable; exit 1 iff any ✗ (CI-usable).
#
# READ-ONLY by contract unless --fix is passed — and even --fix only runs
# repairs that have a deterministic writer (config-line ensure + defaults);
# everything else prints the exact fix command instead of guessing. Fix hints name
# USER COMMANDS (/pw-*) or the user's own pw.config.sh — never raw scripts (plan 27 F1).
#
#   pw-project-doctor.sh <slug>            check only (exit 1 on any ✗)
#   pw-project-doctor.sh <slug> --fix      apply the deterministic repairs
#
# Output sections (human labels; internal check IDs stay in this header for docs/tests):
#   [1/8] Documentation & template lint
#         C10 doc format       pw-doc.sh lint all — structure/field/format validity
#         C11 template currency required dashboard/PLAN lines; no unexpanded scaffold tokens
#   [2/8] RFC data              C12 rfc/META.md well-formed; backend/target vs CURRENT global
#         config. Optional-until-used (rev d owner ruling): an NOT-engaged side-loop warns (·,
#         never fails); once engaged (RFC.md / Target set / revision pushed / any wave yes)
#         findings are real ✗ — the RFC joined this project's flow.
#   [3/8] Plan                 C1 PLAN rows (Status ∈ enum, filled pin, backing task files)
#                              C3 depends_on (resolves over ALL task ids; no cycles)
#   [4/8] Configuration        C6 every config line present/legal/in sync with current floors;
#                              pin enforcement is LIVE work only — accepted-task pin debt is a · (rev f)
#   [5/8] Provider & model pins C8 pw-status.sh provider-audit: ✗ only when a LIVE task's pin is
#                              unusable (unbound/stale-provider, with a /pw-* decision block);
#                              ran-with-a-different-model is history → ·, never ✗ (owner ruling)
#   [6/8] Execution health     C5 stale in-progress runs · C2 live tasks' worktrees/branches
#                              mounted+present; accepted tasks' teardown is expected (·)
#   [7/8] Review gates         C4 PLAN gate readable and passing right now (via preflight)
#   [8/8] Merge requests       C7 dashboard MR table ↔ task Status agreement (merged-but-
#                              unaccepted / accepted-before-merge). Project-local records only —
#                              no live forge call (post-teardown mr-state reads 'unknown' and
#                              /pw-ship keeps the table fresh).
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
CFG="$HERE/pw-config.sh"
DOCL="$HERE/pw-doc.sh"
ST="$HERE/pw-status.sh"
PF="$HERE/pw-preflight.sh"

STALE_DAYS="${PW_DOCTOR_STALE_DAYS:-7}"

FAILS=0; NOTES=0; FIXES=0
ok()   { printf '  ✓ %s\n' "$*"; }
bad()  { printf '  ✗ %s\n' "$*"; FAILS=$((FAILS+1)); }
note() { printf '  · %s\n' "$*"; NOTES=$((NOTES+1)); }
fixed(){ printf '      fixed: %s\n' "$*"; FIXES=$((FIXES+1)); }

SLUG=""; FIX=0
for a in "$@"; do
  case "$a" in
    --fix) FIX=1 ;;
    -h|--help) pw_usage ;;
    *) [ -z "$SLUG" ] || { echo "pw-project-doctor: extra argument '$a' (usage: <slug> [--fix] — see --help)" >&2; exit 2; }
       SLUG="$a" ;;
  esac
done
[ -n "$SLUG" ] || { echo "usage: pw-project-doctor.sh <slug> [--fix]" >&2; exit 2; }
D="$PROJECTS_DIR/$SLUG"
[ -d "$D" ] || { echo "pw-project-doctor: no such project: $SLUG ($D) → fix: check the slug under $PROJECTS_DIR" >&2; exit 2; }
README="$D/README.md"
PLAN="$D/task/PLAN.md"

echo "pw-project-doctor — $SLUG ($(pw_field "$README" Status 2>/dev/null || printf '?'))"

# --- helpers -----------------------------------------------------------------
_now_epoch() { date +%s; }
_mtime_epoch() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
_plan_bold() {  # bold-bullet value, placeholder-safe ("" = unset)
  local v; [ -f "$PLAN" ] || { printf ''; return 0; }
  v="$(pw_field "$PLAN" "$1")"
  case "$v" in "<"*">"|"<"*) printf '%s' "" ;; *) printf '%s' "$v" ;; esac
}

# Machine-field readers (plan 27 F3/F4). A check must test what the field DECLARES: literal
# scaffold tokens (`{{PW_PROJECTS}}`) and trailing annotation prose after the backticked value are
# document defects C11/C6 report separately — they never get to fail an existence check here.
_expand_tokens() {
  local s="$1"
  s="${s//"{{PW_PROJECTS}}"/$PROJECTS_DIR}"
  s="${s//"{{PW_HOME}}"/$PW_HOME}"
  s="${s//"{{PW_REPOS}}"/${PW_REPOS:-$(cd "$PROJECTS_DIR/.." 2>/dev/null && pwd || echo /nonexistent)}}"
  printf '%s' "$s"
}

_raw_val() { # raw field string → machine value: backtick token wins, else first word (prose tolerated)
  local raw="$1" val
  [ -n "$raw" ] || return 0
  case "$raw" in
    *'`'*) val="${raw#*\`}"; val="${val%%\`*}" ;;
    *) val="${raw%%[[:space:]]*}" ;;
  esac
  printf '%s' "$val"
}

_word1() { # first word, backticks stripped — for bullets whose VALUE leads the line ("3 (default 3 — `X`) …")
  printf '%s' "$1" | awk '{print $1}' | tr -d '`'
}

_field_val() { # <file> <field> — resolved + token-expanded; paths lose a trailing slash
  local val
  val="$(_raw_val "$(pw_field "$1" "$2" 2>/dev/null || true)")"; [ -n "$val" ] || return 0
  case "$val" in /*) : ;; *) val="$(printf '%s' "$val" | sed 's|/*$||')" ;; esac
  _expand_tokens "$val"
}

# --- C10+C11: Documentation & template lint -------------------------------------
echo "[1/8] Documentation & template lint"
if LINT_OUT="$("$DOCL" lint all "$SLUG" 2>&1)"; then
  ok "lint all: clean"
else
  case $? in
    1) bad "lint all: structure errors — $(printf '%s\n' "$LINT_OUT" | grep -E '^pw-doc|: ' | head -2 | tr '\n' ' ')" ;;
    *) note "lint all: cannot lint yet (missing docs — normal before the phase exists)" ;;
  esac
fi

if [ -f "$README" ]; then
  missing=""
  grep -q '^- \*\*Status:\*\*' "$README"     || missing="$missing Status:"
  grep -q '^- \*\*One-liner:\*\*' "$README"  || missing="$missing One-liner:"
  grep -q '^- \*\*AI Models:\*\*' "$README"  || missing="$missing AI-Models:"
  grep -q '^- \*\*AI Review:\*\*' "$README"  || missing="$missing AI-Review:"
  # unexpanded scaffold tokens = a render that never landed
  tok="$(grep -oE '<(AI_MODELS_DEFAULT|AI_REVIEW_DEFAULT|PROJECT_NAME|CREATED)>' "$README" | head -1 || true)"
  if [ -n "$missing" ]; then
    if [ "$FIX" = 1 ]; then
      # ensure covers the config lines; then RE-MEASURE — a successful repair must not keep a
      # stale ✗ (the summary reports what is still broken after --fix, not what it found).
      out="$("$CFG" project ensure "$SLUG" 2>&1)" || true
      still=""
      grep -q '^- \*\*AI Models:\*\*' "$README" || still="$still AI-Models:"
      grep -q '^- \*\*AI Review:\*\*' "$README" || still="$still AI-Review:"
      if [ -z "$still" ]; then
        fixed "dashboard config lines ensured (explicit defaults)"
        nm=""
        case "$missing" in *"Status:"*) nm="$nm Status:" ;; esac
        case "$missing" in *"One-liner:"*) nm="$nm One-liner:" ;; esac
        [ -z "$nm" ] || bad "dashboard missing non-config line(s):$nm — owned by the flows (/pw-status Status; /pw-analyze One-liner), never by ensure"
      else
        bad "dashboard missing explicit config line(s):$still"
        echo "      → fix: ensure failed: $out"
      fi
    else
      bad "dashboard missing explicit config line(s):${missing}"
      echo "      → fix: /pw-config $SLUG project ensure   (inserts the missing config lines; Status/One-liner are owned by /pw-* flows)"
    fi
  elif [ -n "$tok" ]; then
    bad "unexpanded template token $tok in the dashboard — scaffold render broke"
    echo "      → fix: tell your agent to replace the token with an explicit value (/pw-config $SLUG project set for config lines), or re-scaffold an empty project with /pw-new"
  else
    ok "dashboard carries the current template's required lines (explicit values, incl. AI Review:)"
  fi
else
  bad "no README.md in project dir"
  echo "      → fix: tell your agent the dashboard README.md is missing — it restores the file from the bundle template (config lines back: /pw-config $SLUG project ensure)"
fi
if [ -f "$PLAN" ]; then
  pm=""
  grep -q '^## Repo manifest'  "$PLAN" || pm="$pm Repo-manifest"
  grep -q '^## Task table'     "$PLAN" || pm="$pm Task-table"
  grep -q '^## Global rules'   "$PLAN" || pm="$pm Global-rules"
  if [ -n "$pm" ]; then
    bad "PLAN missing current-template section(s):$pm"
    echo "      → fix: reconcile task/PLAN.md against task/_TEMPLATE-orchestration-plan.md (or re-run /pw-breakdown)"
  else
    ok "PLAN sections match the current template"
  fi
else
  note "no task/PLAN.md yet (breakdown not run)"
fi
# unexpanded scaffold tokens in later-written docs = literal broken paths everywhere (plan 27 F3):
# scaffold stamps its copies at creation; files written after (task files) must be stamped too.
tokfiles=""
for tf in "$D"/task/T*.md "$D"/task/PLAN.md; do
  [ -f "$tf" ] || continue
  if grep -q '{{PW_' "$tf"; then tokfiles="$tokfiles $(basename "$tf")"; fi
done
if [ -n "$tokfiles" ] && [ "$FIX" = 1 ]; then
  # deterministic writer: the very render scaffold applies to copied templates
  for tf in "$D"/task/T*.md "$D"/task/PLAN.md; do
    [ -f "$tf" ] || continue
    grep -q '{{PW_' "$tf" || continue
    perl -pi -e "s{\Q{{PW_HOME}}\E}{$PW_HOME}g;
                 s{\Q{{PW_PROJECTS}}\E}{$PROJECTS_DIR}g;
                 s{\Q{{PW_REPOS}}\E}{${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}}g" "$tf"
  done
  fixed "scaffold tokens stamped in:$tokfiles"
  after2=""
  for tf in "$D"/task/T*.md "$D"/task/PLAN.md; do
    [ -f "$tf" ] || continue
    if grep -q '{{PW_' "$tf"; then after2="$after2 $(basename "$tf")"; fi
  done
  tokfiles="$after2"
fi
if [ -n "$tokfiles" ]; then
  bad "unexpanded scaffold token(s) in:$tokfiles — paths render literally (a later-written file missed the stamp scaffold applies)"
  echo "      → fix: /pw-doctor --project $SLUG --fix stamps them (same render scaffold applies), or re-run /pw-breakdown for the named files"
fi

# --- C12: RFC ↔ analysis agreement (used-vs-not, rev d 09-28) ---------------
# The side-loop is optional UNTIL the project engages it. Evidence of engagement: rfc/RFC.md
# exists, META's Target set, a revision pushed, or a wave marked published. Not engaged → every
# finding stays a · warning (never fails — the flow isn't part of this project). Engaged → the
# findings become real ✗: the RFC is part of the flow now and broken publish data blocks it.
echo "[2/8] RFC data (optional until used — unused side-loop warns, used side-loop is checked)"
META="$D/rfc/META.md"
if [ ! -f "$META" ]; then
  note "no rfc/META.md — /pw-rfc side-loop not started (optional)"
else
  mbackend="$(pw_field "$META" Backend)"
  mtarget="$(pw_field "$META" Target)"
  mrev="$(pw_field "$META" "Last revision pushed")"
  mw1="$(pw_field "$META" "Wave 1 published")"
  mw2="$(pw_field "$META" "Wave 2 published")"
  want_backend="${PW_RFC_BACKEND:-markdown}"
  rfc_used=0
  if [ -f "$D/rfc/RFC.md" ] || [ -n "$mtarget" ] || [ -n "$mrev" ]; then rfc_used=1; fi
  case "$mw1$mw2" in *yes*) rfc_used=1 ;; esac
  c12emit() { # <bad|note> <msg...> — one gate for the used-vs-unused verdict
    if [ "$rfc_used" = 1 ]; then bad "$@"; else note "$@ (warning only — RFC side-loop not engaged yet)"
  fi; }
  if [ -z "$mbackend" ]; then
    c12emit "rfc/META.md has no Backend: line (the file is agent-owned — never hand-edit it)"
    echo "      → fix: /pw-rfc $SLUG — the RFC side-loop re-stamps Backend with the real configured value on its next run"
  elif [ "$mbackend" != "$want_backend" ]; then
    c12emit "RFC backend drift: META says '$mbackend', current global config says '$want_backend' (a retired/changed PW_RFC_BACKEND)"
    echo "      → fix: /pw-rfc $SLUG to re-init against the current backend, or restore the old backend in pw.config.sh"
  elif [ -z "$mtarget" ]; then
    c12emit "RFC target unset in META — set one before the next publish wave (/pw-rfc $SLUG --target <ref>, or ask your agent)"
  else
    ok "RFC backend '$mbackend' matches the global config; target present"
  fi
  if grep -q '^## Comment tracking' "$META" || [ ! -f "$D/rfc/RFC.md" ]; then
    :
  else
    note "RFC published but no comment-tracking table yet (appears on the first /pw-rfc comments pass)"
  fi
fi

# --- C1: PLAN rows complete ----------------------------------------------------
echo "[3/8] Plan"
if [ ! -f "$PLAN" ]; then
  note "no PLAN yet"
else
  pairs="$(pw_plan_pairs "$PLAN")"
  execs="$(pw_plan_execs "$PLAN")"
  if [ -z "$pairs" ]; then
    note "PLAN task table has no parseable rows yet"
  else
    c1bad=0
    while IFS='|' read -r tid st; do
      [ -n "$tid" ] || continue
      case " todo in-progress verify-failed done accepted " in
        *" $st "*) : ;;
        *) bad "task $tid: Status '$st' is outside the vocabulary (todo → in-progress → verify-failed/done → accepted)"
           echo "      → fix: correct the Status line in task/$tid.md — tell your agent \"set $SLUG $tid status <vocabulary value>\" (accepted/verify-failed flips ride the flows)"
           c1bad=1 ;;
      esac
      [ -f "$D/task/$tid.md" ] || { bad "task $tid: no task/$tid.md behind the PLAN row"
        echo "      → fix: re-run /pw-breakdown $SLUG for the missing task, or remove the stray row from PLAN's table"; c1bad=1; }
    done <<< "$pairs"
    while IFS= read -r ev; do
      case "$ev" in
        "") bad "task table: an 'Execute with:' cell is empty"; echo "      → fix: /pw-config $SLUG project set pin <T0n>=<provider:model> fills both holders"; c1bad=1 ;;
        *[[:space:]]*) bad "task table: 'Execute with: $ev' is not a single provider/model/agent token" ; c1bad=1 ;;
      esac
    done <<< "$execs"
    [ "$c1bad" = 0 ] && ok "every PLAN row: known status, filled pin, backing task file"
  fi
fi

# --- C3: depends_on graph --------------------------------------------------------
# Node universe = EVERY task file id, not only tasks that carry the field (plan 27 F2: an
# edge pointing at a dependency-free task is the normal shape, never "unknown"). Tokens that
# aren't task ids (annotation prose) are reported as hygiene, never as broken edges.

if ! ls "$D"/task/T*.md >/dev/null 2>&1; then
  note "no task files yet"
else
  ids="$(cd "$D/task" && ls T*.md | sed 's/\.md$//')"
  edges=""
  for f in "$D"/task/T*.md; do
    tid="$(basename "$f" .md)"
    # full value (tokens expanded), NOT _field_val — the tokenizer must SEE the annotation
    # prose so it can classify each token as id-vs-annotation instead of silently truncating.
    deps="$(pw_field "$f" depends_on 2>/dev/null || true)"
    deps="$(_expand_tokens "$deps")"
    case "$deps" in ""|none|None|—) continue ;; esac
    edges="$edges$tid $deps
"
  done
  if [ -z "$edges" ]; then
    ok "no depends_on edges (every task independent)"
  else
    c3out="$( { printf 'UNIV\n%s\n' "$ids"; printf 'EDGES\n%s' "$edges"; } | python3 -c '
import sys, re
univ, edges, annot = set(), {}, []
sec = None
for line in sys.stdin:
    line = line.strip()
    if line == "UNIV": sec = "u"; continue
    if line == "EDGES": sec = "e"; continue
    if not line: continue
    if sec == "u":
        univ.add(line); continue
    parts = line.split(None, 1)
    tid = parts[0]
    deps = []
    for tok in re.split(r"[;,\s]+", parts[1] if len(parts) > 1 else ""):
        tok = tok.strip("().,`")
        if not tok or tok.lower() in ("none", "—"): continue
        if re.fullmatch(r"T[0-9]+", tok): deps.append(tok)
        else: annot.append(f"{tid}:{tok}")
    edges[tid] = deps
missing = [(t, d) for t in sorted(edges) for d in edges[t] if d not in univ]
color, cycle = {}, []
def walk(n, path):
    color[n] = 1
    for m in edges.get(n, []):
        if m not in univ: continue
        if color.get(m) == 1:
            cycle.extend(path + [m]); return True
        if color.get(m, 0) == 0 and walk(m, path + [m]): return True
    color[n] = 2
    return False
for t in sorted(univ):
    if color.get(t, 0) == 0 and walk(t, [t]): break
if missing:
    print("MISSING " + ", ".join(f"{t}->{d}" for t, d in missing))
if cycle:
    print("CYCLE " + " -> ".join(cycle))
if annot:
    print("ANNOT " + ", ".join(sorted(set(annot))))
if not missing and not cycle:
    print("OK")
' 2>&1)" || c3out="PYERR $c3out"
    c3=0
    if printf '%s\n' "$c3out" | grep -q '^MISSING'; then
      bad "depends_on references unknown tasks — $(printf '%s\n' "$c3out" | grep '^MISSING' | sed 's/^MISSING //')"
      echo "      → fix: correct the field (or the task id) in the named task file"
      c3=1
    fi
    if printf '%s\n' "$c3out" | grep -q '^CYCLE'; then
      bad "depends_on cycle — $(printf '%s\n' "$c3out" | grep '^CYCLE' | sed 's/^CYCLE //')"
      echo "      → fix: break the loop in the task files' depends_on fields"
      c3=1
    fi
    annot="$(printf '%s\n' "$c3out" | grep '^ANNOT' | sed 's/^ANNOT //' || true)"
    if printf '%s\n' "$c3out" | grep -q '^PYERR'; then
      note "depends_on check unavailable (python3: $c3out)"
    else
      [ -n "$annot" ] && note "depends_on carries non-id tokens (read as annotation, not edges): $annot"
      if [ "$c3" = 0 ]; then
        if [ -n "$annot" ]; then :; else ok "depends_on references resolve, no cycles"; fi
      fi
    fi
  fi
fi

# --- C6: config validity + sync with the CURRENT global config --------------------
echo "[4/8] Configuration"
# dashboard lines: present + legal (explicit-line doctrine: absence is a defect, not silence)
ai_line="$(grep '^- \*\*AI Review:\*\*' "$README" 2>/dev/null | head -1 || true)"
am_line="$(grep '^- \*\*AI Models:\*\*' "$README" 2>/dev/null | head -1 || true)"
c6bad=0
if [ -z "$ai_line" ]; then : # absence is C11's ✗ (with the ensure fix) — never reported twice
else
  for kv in $(printf '%s' "$ai_line" | sed 's/^- \*\*AI Review:\*\*[[:space:]]*//'); do
    mode="${kv#*=}"
    case "$mode" in off|advisory|auto) : ;; *) bad "AI Review row '$kv' — mode outside off|advisory|auto"; c6bad=1 ;; esac
  done
fi
if [ -z "$am_line" ]; then : # presence owned by C11
else
  for kv in $(printf '%s' "$am_line" | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//'); do
    case "$kv" in *=*) : ;; *) bad "AI Models row '$kv' — expected role=value"; c6bad=1; continue ;; esac
    val="${kv#*=}"
    case "$val" in —|-) continue ;; esac
    prov="${val%%:*}"
    case "$val" in *:*) : ;; *) bad "AI Models row '$kv' — expected provider:model or —"; c6bad=1; continue ;; esac
    inprov=0; for p in "${PW_PROVIDERS[@]}"; do [ "$p" = "$prov" ] && inprov=1; done
    [ "$inprov" = 1 ] || { bad "AI Models row '$kv' — provider '$prov' is not in the CURRENT pw.config.sh PW_PROVIDERS (${PW_PROVIDERS[*]})"; c6bad=1; }
  done
fi
# PLAN config bullets
rout="$(_word1 "$(_plan_bold Routing)")"; [ -n "$rout" ] || rout="$PW_ROUTE_DEFAULT"
case "$rout" in auto|subagent|headless) : ;; *) bad "PLAN '- **Routing:**' value '$rout' outside auto|subagent|headless"; c6bad=1 ;; esac
lim="$(_word1 "$(_plan_bold "AI execution limit")")"; [ -n "$lim" ] || lim="$PW_MAX_SELF_REPAIR"
case "$lim" in ''|*[!0-9]*) [ "$lim" = "$PW_MAX_SELF_REPAIR" ] || { bad "PLAN '- **AI execution limit:**' value '$(_plan_bold "AI execution limit")' is not an integer"; echo "      → fix: tell your agent to set the limit to a plain number (the guidance text belongs in the comment, not the field)"; c6bad=1; } ;; esac
pb="$(_word1 "$(_plan_bold "Produced by")")"
if [ -n "$pb" ]; then
  inprov=0; for p in "${PW_PROVIDERS[@]}"; do [ "$p" = "$pb" ] && inprov=1; done
  [ "$inprov" = 1 ] || { bad "PLAN 'Produced by: $pb' — provider no longer enabled in pw.config.sh (PW_PROVIDERS: ${PW_PROVIDERS[*]})"; c6bad=1; }
fi
# per-task pins: shape + provider-membership (colon form); catalog availability is C8's axis
if ls "$D"/task/T*.md >/dev/null 2>&1; then
  # Rev f owner ruling (09-28): closed work is history. A pin problem on an ACCEPTED task is
  # counted as a · (same stance as C8), never an ✗ — enforcement applies to live work only.
  c6hist=0
  for f in "$D"/task/T*.md; do
    raw="$(pw_field "$f" "Execute with" 2>/dev/null || true)"
    pin="$(_raw_val "$raw")"
    tid="$(basename "$f" .md)"
    problem=""
    case "$raw" in
      "") problem="empty" ;;
      *'`'*) : ;;  # quoted machine value — trailing prose tolerated (reader takes the token)
      *[[:space:]]*|*,*) problem="prose" ;;
    esac
    if [ -z "$problem" ] && [ -n "$pin" ]; then
      case "$pin" in
        *:*) prov="${pin%%:*}"; inprov=0; for p in "${PW_PROVIDERS[@]}"; do [ "$p" = "$prov" ] && inprov=1; done
             [ "$inprov" = 1 ] || problem="stale-provider" ;;
        *) : ;;  # provider-implicit form (bare alias `sonnet`, agent `pw-executor`) — legal shape;
                 # C8's audit judges whether it resolves
      esac
    fi
    if [ -n "$problem" ]; then
      if [ "$(pw_field "$f" Status)" = "accepted" ]; then
        c6hist=$((c6hist+1))
      else
        case "$problem" in
          empty) bad "$tid: '- **Execute with:**' empty" ; echo "      → fix: /pw-config $SLUG project set pin $tid=<provider:model>" ;;
          prose) bad "$tid: 'Execute with: $raw' is prose, not a single pin (guidance text leaked into the field)" ; echo "      → fix: /pw-config $SLUG project set pin $tid=<provider:model> — the reasoning belongs in Why:" ;;
          *) bad "$tid: pin '$pin' — provider '${pin%%:*}' not in current PW_PROVIDERS (${PW_PROVIDERS[*]})" ; echo "      → fix: /pw-config $SLUG project set pin $tid=<provider:model> with a current provider, or re-enable it in pw.config.sh (PW_PROVIDERS)" ;;
        esac
        c6bad=1
      fi
    fi
  done
  [ "$c6hist" -gt 0 ] && note "$c6hist accepted task(s) carry pins outside the current config — closed work stays history, nothing to re-pin"
fi
[ "$c6bad" = 0 ] && ok "all config lines present, legal, and consistent with the current global config"

# --- C8: provider & model pins -----------------------------------------------------
# The check is PIN USABILITY, not history: an ✗ fires only when a LIVE task's pin cannot resolve
# against the current config (unbound/stale-provider), and carries a finite decision block in
# command form. "Ran with a different model" (mismatch) is intent-vs-history — a ·, never a fail
# (owner ruling 09-28: users may freely re-pin; the ledger stays the record of what ran).
echo "[5/8] Provider & model pins"
if pa_out="$("$ST" provider-audit "$SLUG" 2>&1)"; then
  ok "every task pin resolves against the current providers/models, and rows that ran match them"
else
  pa_rc=$?
  case "$pa_rc" in
    1)
      c8bad=""; c8hist=0; c8drift=0; c8provs=""
      while IFS='|' read -r ptid pfields; do
        case "$ptid" in T[0-9]*) : ;; *) continue ;; esac
        case "$pfields" in *verdict=ok*) continue ;; esac
        verdict="${pfields##*verdict=}"
        pst="$(pw_field "$D/task/$ptid.md" Status 2>/dev/null || true)"
        case "$verdict" in
          mismatch)
            c8drift=$((c8drift+1)) ;;
          *)
            if [ "$pst" = "accepted" ]; then
              c8hist=$((c8hist+1))
            else
              c8bad="$c8bad      $ptid|${pfields}
"
              _pv="$(printf '%s' "$pfields" | sed -E 's/expected=//; s/:.*//')"
              case " $c8provs " in *" $_pv "*) : ;; *) c8provs="$c8provs $_pv" ;; esac
            fi ;;
        esac
      done <<< "$(printf '%s\n' "$pa_out" | grep -E '^T[0-9]+\|')"
      [ "$c8drift" -gt 0 ] && note "$c8drift row(s) ran with a different model than the current pin — the ledger records history, the pin records intent; no action (re-run /pw-execute to refresh)"
      [ "$c8hist" -gt 0 ] && note "$c8hist accepted row(s) carry a pin that no longer resolves against the current config — history only, nothing to ship with"
      if [ -n "$c8bad" ]; then
        bad "live task pins are not usable against the current config:"
        printf '%s' "$c8bad"
        echo "      → decision (one per row):"
        echo "        (a) re-pin it:  /pw-config $SLUG project set pin <T0n>=<provider:model>   (validated at write)"
        _c8v=""
        for _pv in $c8provs; do _u="$(printf '%s' "$_pv" | tr '[:lower:]' '[:upper:]')"; _c8v="$_c8v PW_${_u}_API_PROVIDERS"; done
        echo "        (b) or restore the retired scope in pw.config.sh (${_c8v# } for the flagged provider(s))"
      fi
      ;;
    *) note "provider-audit can't run yet: $(printf '%s' "$pa_out" | head -1 | sed -E 's/^pw-[a-z-]+: //')" ;;
  esac
fi

# --- C5: stale runs ----------------------------------------------------------------
echo "[6/8] Execution health"
now="$(_now_epoch)"; cutoff=$((STALE_DAYS * 86400)); c5=0
if ls "$D"/task/T*.md >/dev/null 2>&1; then
  for f in "$D"/task/T*.md; do
    [ "$(pw_field "$f" Status)" = "in-progress" ] || continue
    tid="$(basename "$f" .md)"
    newest="$(_mtime_epoch "$f")"
    wt="$(_field_val "$f" Worktree)"
    if [ -n "$wt" ]; then
      case "$wt" in /*) wtp="$wt" ;; *) wtp="$D/$wt" ;; esac
      [ -d "$wtp" ] && newest="$(_mtime_epoch "$wtp")"
    fi
    lg="$(_mtime_epoch "$D/LOG.md")"; [ "$lg" -gt "$newest" ] && newest="$lg"
    if [ $((now - newest)) -gt "$cutoff" ]; then
      bad "task $tid: in-progress with no worktree/LOG activity in $(( (now - newest) / 86400 ))d (stale — resume or reset it)"
      echo "      → fix: /pw-execute $SLUG $tid (resume), or set its Status honestly"
      c5=1
    fi
  done
  [ "$c5" = 0 ] && ok "no stale in-progress tasks (threshold ${STALE_DAYS}d — PW_DOCTOR_STALE_DAYS)"
else
  note "no task files yet"
fi

# --- C2: worktree/branch pairs ------------------------------------------------------
# Status-aware (plan 27 F5): an accepted task's missing worktree/branch is the EXPECTED
# post-close/post-merge shape (teardown is /pw-close's job, branch deletion is the forge's) —
# reported as ·, never ✗, and never in disagreement with C7. Mount + branch existence are
# required for live tasks only (todo / in-progress / verify-failed / done-pre-ship).

c2=0; c2n=0; c2torn=0; c2mounted=0
if ls "$D"/task/T*.md >/dev/null 2>&1; then
  for f in "$D"/task/T*.md; do
    tid="$(basename "$f" .md)"
    br="$(_field_val "$f" Branch)"
    wt="$(_field_val "$f" Worktree)"
    repo="$(_field_val "$f" Repo)"
    st="$(pw_field "$f" Status)"
    [ -n "$wt" ] || continue
    c2n=$((c2n+1))
    live=1; case "$st" in accepted) live=0 ;; esac
    case "$wt" in /*) wtp="$wt" ;; *) wtp="$D/$wt" ;; esac
    if [ ! -d "$wtp" ]; then
      if [ "$live" = 1 ]; then
        bad "$tid: declared worktree '$wt' not mounted"
        echo "      → fix: /pw-execute $SLUG $tid re-creates the worktree for a live task"
        c2=1
      else
        c2torn=$((c2torn+1))
      fi
    elif [ "$live" = 0 ]; then
      c2mounted=$((c2mounted+1))
    fi
    if [ "$live" = 1 ] && [ -n "$br" ] && [ -d "$PW_REPOS/$repo/.git" ]; then
      git -C "$PW_REPOS/$repo" show-ref --verify --quiet "refs/heads/$br" 2>/dev/null \
        || git -C "$PW_REPOS/$repo" show-ref --verify --quiet "refs/remotes/origin/$br" 2>/dev/null \
        || { bad "$tid: branch '$br' not found in repo '$repo' (local or origin/*)"; c2=1; }
    elif [ "$live" = 1 ] && [ -n "$br" ]; then
      note "$tid: repo '$repo' not under PW_REPOS — branch existence unchecked (can't check ≠ broken)"
    fi
  done
fi
if [ "$c2n" = 0 ]; then note "no worktrees declared yet"
else
  [ "$c2torn" -gt 0 ] && note "$c2torn accepted task(s) with worktrees torn down at close (expected — the MR table is the merge truth)"
  [ "$c2mounted" -gt 0 ] && note "$c2mounted accepted task(s) still carry a mounted worktree (harmless — /pw-close removes it)"
  if [ "$c2" = 0 ] && [ "$c2torn" = 0 ]; then ok "every live task's worktree/branch pair exists"; fi
fi

# --- C4: review gates right now ------------------------------------------------------
echo "[7/8] Review gates"
if [ ! -f "$D/task/review/PLAN.review.md" ]; then
  note "no PLAN review file yet (created on first /pw-review)"
else
  if pf_out="$("$PF" review "$SLUG" plan 2>&1)"; then
    ok "PLAN gate: sign-off valid, passes right now"
  else
    bad "PLAN gate failing right now: $(printf '%s' "$pf_out" | head -1)"
    echo "      → fix: /pw-review $SLUG (then sign off task/review/PLAN.review.md — the sign-off itself is human)"
  fi
fi

# --- C7: MR ↔ task agreement ----------------------------------------------------------
# Source = the dashboard's own MR table (🤖 filled and kept fresh by /pw-ship; the plan-23
# _dashboard_fill primitives write it) cross-read with each task's Status. No live forge call:
# after teardown the worktree-based mr-state reader can't reach the forge and used to spray
# per-task "unknown" noise (owner ruling 09-28: the project's record is the point).
echo "[8/8] Merge requests ↔ task status"
c7=0; c7n=0
if ls "$D"/task/T*.md >/dev/null 2>&1; then
  for f in "$D"/task/T*.md; do
    tid="$(basename "$f" .md)"
    state="$(awk -F'|' -v t="$tid" '/^## Merge requests/{sec=1; next} /^##[ ]/{sec=0} sec && $2 ~ ("^[ ]*" t "[ ]*$") { gsub(/[ `*]/, "", $6); print $6; exit }' "$README" 2>/dev/null || true)"
    st="$(pw_field "$f" Status)"
    case "$state" in
      merged)
        c7n=$((c7n+1))
        [ "$st" = "accepted" ] || { bad "$tid: dashboard MR says merged but task Status is '$st' — the acceptance step was skipped"; echo "      → fix: accept it — tell your agent \"accept $SLUG $tid\" (the acceptance flow syncs task file + PLAN row + dashboard; you can also flip the Status in the dashboard yourself)"; c7=1; } ;;
      open|on-hold)
        c7n=$((c7n+1))
        [ "$st" = "accepted" ] && { bad "$tid: task accepted but the dashboard MR row is still $state — acceptance before merge"; c7=1; } ;;
      "")
        mr="$(pw_task_mr_url "$f" 2>/dev/null || true)"
        case "$mr" in http*) c7n=$((c7n+1)); note "$tid: MR recorded in the task file but no dashboard MR row — /pw-ship fills the table";; esac ;;
      *) c7n=$((c7n+1)); note "$tid: dashboard MR state '$state' unrecognized (left as-is — never guessed)" ;;
    esac
  done
fi
if [ "$c7n" = 0 ]; then note "no MR-backed tasks yet (nothing shipped — normal before /pw-ship)"
elif [ "$c7" = 0 ]; then ok "dashboard MR states and task statuses agree"
fi

# --- verdict ---------------------------------------------------------------------------
echo
if [ "$FAILS" -eq 0 ]; then
  echo "project-doctor $SLUG: 0 ✗, $NOTES ·"
  [ "$FIX" = 1 ] && echo "  ($FIXES deterministic fix(es) applied)"
  exit 0
fi
if [ "$FIX" = 1 ] && [ "$FIXES" -gt 0 ]; then
  echo "project-doctor $SLUG: $FAILS ✗ remaining after $FIXES deterministic fix(es) — re-run to confirm"
fi
echo "project-doctor $SLUG: $FAILS ✗, $NOTES ·  (each ✗ above carries its → fix: line)"
exit 1
