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
# everything else prints the exact fix command instead of guessing.
#
#   pw-project-doctor.sh <slug>            check only (exit 1 on any ✗)
#   pw-project-doctor.sh <slug> --fix      apply the deterministic repairs
#
# Checks (ordered along the project's own workflow):
#   C10 doc format          pw-doc.sh lint all          — structure/field/format validity
#   C11 template currency   required dashboard/PLAN lines; no unexpanded template tokens
#   C12 RFC ↔ analysis      rfc/META.md well-formed; backend/target legal under CURRENT
#                           global config (a retired backend lights up here)
#   C1  PLAN rows           Status ∈ enum, Execute with: filled, task files exist
#   C3  depends_on          references resolve; no cycles
#   C6  config validity     every config line present / legal / resolvable / in sync with
#                           the current pw.config.sh floors (delegates to pw-config show)
#   C8  provider/executor   pw-status.sh provider-audit verdicts (PLAN cell vs task pin vs
#                           actually-used vs live catalog)
#   C5  stale runs          in-progress tasks with no recent worktree/LOG activity
#   C2  worktree/branch     declared worktrees mounted; declared branches exist in the repo
#   C4  review gates        PLAN gate readable and passing right now (via preflight)
#   C7  MR ↔ task           merged-but-unaccepted / accepted-but-open MRs (mr-state readers)
#   C9  verification kinds  forward reference — not enforced yet
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
SHIP="$HERE/pw-ship.sh"

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

# --- C10: doc format (lint) — reuse the linter, never re-implement it ---------
echo "[scaffold / adopt] C10 doc format"
if LINT_OUT="$("$DOCL" lint all "$SLUG" 2>&1)"; then
  ok "lint all: clean"
else
  case $? in
    1) bad "lint all: structure errors — $(printf '%s\n' "$LINT_OUT" | grep -E '^pw-doc|: ' | head -2 | tr '\n' ' ')" ;;
    *) note "lint all: cannot lint yet (missing docs — normal before the phase exists)" ;;
  esac
fi

# --- C11: template currency ---------------------------------------------------
echo "[scaffold / adopt] C11 template currency"
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
      echo "      → fix: $CFG project ensure $SLUG   (inserts the missing config lines; Status/One-liner are owned by /pw-* flows)"
    fi
  elif [ -n "$tok" ]; then
    bad "unexpanded template token $tok in the dashboard — scaffold render broke"
    echo "      → fix: re-create the project from template, or replace the token with an explicit value via $CFG project"
  else
    ok "dashboard carries the current template's required lines (explicit values, incl. AI Review:)"
  fi
else
  bad "no README.md in project dir"
  echo "      → fix: restore the dashboard from $PW_HOME/template/PROJECT.template.md (scaffold.sh refuses over an existing dir)"
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

# --- C12: RFC ↔ analysis agreement (side-loop aware: no RFC yet = fine) -------
echo "[analysis → publish] C12 RFC ↔ analysis agreement"
META="$D/rfc/META.md"
if [ ! -f "$META" ]; then
  note "no rfc/META.md — /pw-rfc side-loop not started (optional)"
else
  mbackend="$(pw_field "$META" Backend)"
  mtarget="$(pw_field "$META" Target)"
  want_backend="${PW_RFC_BACKEND:-markdown}"
  if [ -z "$mbackend" ]; then
    bad "rfc/META.md has no Backend: line (the file is 🤖-owned — never hand-edit it)"
    echo "      → fix: pw-rfc.sh state $SLUG Backend ${want_backend} (pw-rfc.sh init re-stamps it with the REAL configured backend)"
  elif [ "$mbackend" != "$want_backend" ]; then
    bad "RFC backend drift: META says '$mbackend', current global config says '$want_backend' (a retired/changed PW_RFC_BACKEND)"
    echo "      → fix: pw-rfc.sh state $SLUG Backend $want_backend (after re-running pw-rfc init for the new target) or restore the old backend in pw.config.sh"
  elif [ -z "$mtarget" ]; then
    note "RFC target unset in META (set one before the next publish wave)"
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
echo "[breakdown / PLAN] C1 PLAN rows"
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
        *) bad "task $tid: Status '$st' is outside the vocabulary (todo → in-progress → verify-failed/done → accepted)"; c1bad=1 ;;
      esac
      [ -f "$D/task/$tid.md" ] || { bad "task $tid: no task/$tid.md behind the PLAN row"; c1bad=1; }
    done <<< "$pairs"
    while IFS= read -r ev; do
      case "$ev" in
        "") bad "task table: an 'Execute with:' cell is empty"; c1bad=1 ;;
        *[[:space:]]*) bad "task table: 'Execute with: $ev' is not a single provider/model/agent token" ; c1bad=1 ;;
      esac
    done <<< "$execs"
    [ "$c1bad" = 0 ] && ok "every PLAN row: known status, filled pin, backing task file"
  fi
fi

# --- C3: depends_on graph --------------------------------------------------------
echo "[breakdown / PLAN] C3 depends_on"
if ! ls "$D"/task/T*.md >/dev/null 2>&1; then
  note "no task files yet"
else
  edges=""
  for f in "$D"/task/T*.md; do
    tid="$(basename "$f" .md)"
    deps="$(pw_field "$f" depends_on)"
    [ -n "$deps" ] || continue
    case "$deps" in none|None|—) continue ;; esac
    edges="$edges$tid $deps
"
  done
  if [ -z "$edges" ]; then
    ok "no depends_on edges (every task independent)"
  else
    c3out="$(printf '%s' "$edges" | python3 -c '
import sys
dep = {}
for line in sys.stdin:
    parts = line.split()
    if len(parts) < 2: continue
    tid = parts[0]
    dep[tid] = [d.strip() for d in " ".join(parts[1:]).replace(";", ",").split(",") if d.strip() and d.strip() != "none"]
missing = [(t, d) for t in dep for d in dep[t] if d not in dep]
color = {}
cycle = None
def walk(n, path):
    global cycle
    color[n] = 1
    for m in dep.get(n, []):
        if m not in dep: continue
        if color.get(m) == 1:
            cycle = " -> ".join(path + [m]); return
            return
        if color.get(m, 0) == 0:
            walk(m, path + [m])
    color[n] = 2
for t in sorted(dep):
    if color.get(t, 0) == 0:
        walk(t, [t])
if missing:
    print("MISSING " + ", ".join(f"{t}->{d}" for t, d in missing))
if cycle:
    print("CYCLE " + cycle)
if not missing and not cycle:
    print("OK")
' 2>&1)" || c3out="PYERR $c3out"
    case "$c3out" in
      OK*) ok "depends_on references resolve, no cycles" ;;
      MISSING*) bad "depends_on references unknown tasks — ${c3out#MISSING }"; echo "      → fix: correct the field (or the task id) in the named task file" ;;
      CYCLE*) bad "depends_on cycle — ${c3out#CYCLE }"; echo "      → fix: break the loop in the task files' depends_on fields" ;;
      *) note "depends_on check unavailable (python3: $c3out)" ;;
    esac
  fi
fi

# --- C6: config validity + sync with the CURRENT global config --------------------
echo "[breakdown / PLAN] C6 config validity (vs current global config)"
# dashboard lines: present + legal (explicit-line doctrine: absence is a defect, not silence)
ai_line="$(grep '^- \*\*AI Review:\*\*' "$README" 2>/dev/null | head -1 || true)"
am_line="$(grep '^- \*\*AI Models:\*\*' "$README" 2>/dev/null | head -1 || true)"
c6bad=0
if [ -z "$ai_line" ]; then bad "dashboard has no '- **AI Review:**' line (every config line must be explicit — 'off' is a legal value)"; c6bad=1
else
  for kv in $(printf '%s' "$ai_line" | sed 's/^- \*\*AI Review:\*\*[[:space:]]*//'); do
    mode="${kv#*=}"
    case "$mode" in off|advisory|auto) : ;; *) bad "AI Review row '$kv' — mode outside off|advisory|auto"; c6bad=1 ;; esac
  done
fi
if [ -z "$am_line" ]; then bad "dashboard has no '- **AI Models:**' line (explicit-line doctrine)"; c6bad=1
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
rout="$(_plan_bold Routing)"; [ -n "$rout" ] || rout="$PW_ROUTE_DEFAULT"
case "$rout" in auto|subagent|headless) : ;; *) bad "PLAN '- **Routing:**' value '$rout' outside auto|subagent|headless"; c6bad=1 ;; esac
lim="$(_plan_bold "AI execution limit")"; [ -n "$lim" ] || lim="$PW_MAX_SELF_REPAIR"
case "$lim" in ''|*[!0-9]*) [ "$lim" = "$PW_MAX_SELF_REPAIR" ] || { bad "PLAN '- **AI execution limit:**' value '$lim' is not an integer"; c6bad=1; } ;; esac
pb="$(_plan_bold "Produced by")"
if [ -n "$pb" ]; then
  inprov=0; for p in "${PW_PROVIDERS[@]}"; do [ "$p" = "$pb" ] && inprov=1; done
  [ "$inprov" = 1 ] || { bad "PLAN 'Produced by: $pb' — provider no longer enabled in pw.config.sh (PW_PROVIDERS: ${PW_PROVIDERS[*]})"; c6bad=1; }
fi
# per-task pins: shape + provider-membership (colon form); catalog availability is C8's axis
if ls "$D"/task/T*.md >/dev/null 2>&1; then
  for f in "$D"/task/T*.md; do
    pin="$(pw_field "$f" "Execute with")"
    tid="$(basename "$f" .md)"
    case "$pin" in
      "") bad "$tid: '- **Execute with:**' empty" ; c6bad=1 ;;
      *[[:space:]]*|*,*) bad "$tid: 'Execute with: $pin' is prose, not a single pin (guidance text leaked into the field)" ; c6bad=1 ;;
      *:*) prov="${pin%%:*}"; inprov=0; for p in "${PW_PROVIDERS[@]}"; do [ "$p" = "$prov" ] && inprov=1; done
           [ "$inprov" = 1 ] || { bad "$tid: pin '$pin' — provider '$prov' not in current PW_PROVIDERS (${PW_PROVIDERS[*]})"; c6bad=1; } ;;
    esac
  done
fi
[ "$c6bad" = 0 ] && ok "all config lines present, legal, and consistent with the current global config"

# --- C8: provider/executor audit (delegate — never re-implement) ------------------
echo "[execute] C8 provider/executor audit"
if pa_out="$("$ST" provider-audit "$SLUG" 2>&1)"; then
  ok "provider-audit: every spawned row ok (or never-run)"
else
  case $? in
    1) bad "provider-audit flagged rows:"
       printf '%s\n' "$pa_out" | grep -vE '\|verdict=ok(\||$)' | sed 's/^/      /' | head -12 || true
       echo "      → fix: re-pin the PLAN rows (pw-config project set …) or record what actually ran — docs/EXECUTION.md §The per-spawn ledger" ;;
    *) note "provider-audit can't run yet (no PLAN/LOG to audit): $(printf '%s' "$pa_out" | head -1)" ;;
  esac
fi

# --- C5: stale runs ----------------------------------------------------------------
echo "[execute] C5 stale runs"
now="$(_now_epoch)"; cutoff=$((STALE_DAYS * 86400)); c5=0
if ls "$D"/task/T*.md >/dev/null 2>&1; then
  for f in "$D"/task/T*.md; do
    [ "$(pw_field "$f" Status)" = "in-progress" ] || continue
    tid="$(basename "$f" .md)"
    newest="$(_mtime_epoch "$f")"
    wt="$(pw_field "$f" Worktree | sed -E 's/`//g')"
    [ -n "$wt" ] && [ -d "$D/$wt" ] && newest="$(_mtime_epoch "$D/$wt")"
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
echo "[execute → ship] C2 worktrees and branches"
c2=0; c2n=0
if ls "$D"/task/T*.md >/dev/null 2>&1; then
  for f in "$D"/task/T*.md; do
    tid="$(basename "$f" .md)"
    br="$(pw_field "$f" Branch | sed -E 's/`//g')"
    wt="$(pw_field "$f" Worktree | sed -E 's/`//g' | sed -E 's|/$||')"
    repo="$(pw_field "$f" Repo)"
    [ -n "$wt" ] || continue
    c2n=$((c2n+1))
    [ -d "$D/$wt" ] || { bad "$tid: declared worktree '$wt' not mounted"; c2=1; }
    if [ -n "$br" ] && [ -d "$PW_REPOS/$repo/.git" ]; then
      git -C "$PW_REPOS/$repo" show-ref --verify --quiet "refs/heads/$br" 2>/dev/null \
        || git -C "$PW_REPOS/$repo" show-ref --verify --quiet "refs/remotes/origin/$br" 2>/dev/null \
        || { bad "$tid: branch '$br' not found in repo '$repo' (local or origin/*)"; c2=1; }
    elif [ -n "$br" ]; then
      note "$tid: repo '$repo' not under PW_REPOS — branch existence unchecked (can't check ≠ broken)"
    fi
  done
fi
if [ "$c2n" = 0 ]; then note "no worktrees declared yet"
elif [ "$c2" = 0 ]; then ok "every declared worktree/branch pair exists"
else echo "      → fix: pw-worktree.sh create <slug> <T0n> <repo> <base-branch> re-mounts a missing worktree"; fi

# --- C4: review gates right now ------------------------------------------------------
echo "[review] C4 gates"
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
echo "[ship] C7 MR ↔ task agreement"
c7=0; c7n=0
if ls "$D"/task/T*.md >/dev/null 2>&1; then
  for f in "$D"/task/T*.md; do
    tid="$(basename "$f" .md)"
    mr="$(pw_task_mr_url "$f")"
    case "$mr" in http*) : ;; *) continue ;; esac
    c7n=$((c7n+1))
    st="$(pw_field "$f" Status)"
    state="$("$SHIP" mr-state "$SLUG" "$tid" 2>/dev/null || true)"
    case "$state" in
      merged)
        [ "$st" = "accepted" ] || { bad "$tid: MR already merged but task Status is '$st' — the acceptance step was skipped"; echo "      → fix: pw-status.sh task-accept $SLUG $tid"; c7=1; } ;;
      open)
        [ "$st" = "accepted" ] && { bad "$tid: task accepted but the MR is still OPEN — acceptance before merge"; c7=1; } ;;
      *) note "$tid: forge state unknown/unverifiable (left as-is — never guessed)" ;;
    esac
  done
fi
if [ "$c7n" = 0 ]; then note "no MR-backed tasks yet"
elif [ "$c7" = 0 ]; then ok "MR states and task states agree (or were unverifiable)"
fi

# --- C9: forward reference -------------------------------------------------------------
echo "[ship] C9 verification readiness"
note "typed verify kinds not enforced yet (forward reference; activates with the verification-kinds plan)"

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
