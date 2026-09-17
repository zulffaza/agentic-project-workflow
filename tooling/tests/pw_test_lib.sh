# shellcheck shell=bash
# ============================================================================
# pw_test_lib.sh — shared plumbing for the tooling test suite (plan 16).
#
# Sourced by: tests/pwtest.sh (the runner) and by every script's `--selftest`
# (via tests/selftest_entry.sh). Provides:
#   • tiny assertion layer (PASS/FAIL/SKIP counters, one FAIL line each)
#   • fixture builders: F1 scaffold / F2 mid-lifecycle / F3 hostile — GENERATED
#     from the CURRENT template/ at run time (P1). Superseded layouts are data
#     handled by the read-only corpus tier (P9), never fixtures.
#   • fake gh/glab on PATH (tests/bin) — nothing here talks to a real forge
# Globals the assert layer needs: PWTEST_ROOT (and PWTEST_TESTSDIR=tests dir).
# ============================================================================

TOOL_DIR="${TOOL:-$PWTEST_TOOLING_DIR}"
PWTEST_PASS=0; PWTEST_FAIL=0; PWTEST_SKIP=0
# In-place sed on both BSD (`sed -i ''`) and GNU (`sed -i`) — BSD detected.
sedi() {
  if sed --version >/dev/null 2>&1; then sed -i "$@"
  else local f="${!#}"; sed -i '' "${@:1:$#-1}" "$f"; fi
}
PWTEST_VERBOSE="${PWTEST_VERBOSE:-0}"

pwtest_note(){ printf 'TEST %s\n' "$1" >&2; }
pwtest_ok()  { PWTEST_PASS=$((PWTEST_PASS+1)); [ "$PWTEST_VERBOSE" = 1 ] && printf '  ok   %s\n' "$1" >&2; return 0; }
pwtest_bad() { PWTEST_FAIL=$((PWTEST_FAIL+1)); printf '  FAIL %s — %s\n' "$1" "$2" >&2; }
pwtest_skip(){ PWTEST_SKIP=$((PWTEST_SKIP+1)); printf '  skip %s (%s)\n' "$1" "${2:-}" >&2; return 0; }

# pwtest_rc <want|any> <label> [cmd…] — run capturing out/err to $PWTEST_ROOT/out.$/err.$
pwtest_rc() {
  local want="$1" label="$2"; shift 2
  PWTEST_OUT="$PWTEST_ROOT/out.$$" PWTEST_ERR="$PWTEST_ROOT/err.$$"
  if "$@" >"$PWTEST_OUT" 2>"$PWTEST_ERR"; then PWTEST_RC=0; else PWTEST_RC=$?; fi
  PWTEST_BOTH="$PWTEST_ROOT/both"; cat "$PWTEST_OUT" "$PWTEST_ERR" >"$PWTEST_BOTH"
  if [ "$want" = any ] || [ "$PWTEST_RC" = "$want" ]; then
    pwtest_ok "$label (rc=$PWTEST_RC)"
  else
    pwtest_bad "$label" "rc=$PWTEST_RC want=$want; err: $(head -c 200 "$PWTEST_ERR" | tr '\n' ' ')"
  fi
}
pwtest_re()  { grep -qE -- "$1" "$PWTEST_OUT" && pwtest_ok "$2" || pwtest_bad "$2" "stdout lacks /$1/: $(head -c 150 "$PWTEST_OUT" | tr '\n' ' ')"; }
pwtest_err() { grep -qE -- "$1" "$PWTEST_ERR" && pwtest_ok "$2" || pwtest_bad "$2" "stderr lacks /$1/: $(head -c 150 "$PWTEST_ERR" | tr '\n' ' ')"; }
pwtest_fix() {
  grep -qE '→ fix:|fix:|fixes|run |/pw-|pw-lib|scaffold|try --help|[Uu]sage|expected:|check the slug|create it with|check |glab auth|is it authenticated|authenticat|repair with' "$PWTEST_ERR" \
    && pwtest_ok "$1 (→ fix:)" || pwtest_bad "$1 (→ fix:)" "non-zero with bare stderr: $(head -c 140 "$PWTEST_ERR"|tr '\n' ' ')"
}
pwtest_eq() { [ "$2" = "$3" ] && pwtest_ok "$1" || pwtest_bad "$1" "want [$2] got [$3]"; }
pwtest_grep_file() { grep -qE -- "$1" "$3" && pwtest_ok "$2" || pwtest_bad "$2" "no /$1/ in $3"; }

pwtest_summary() {
  printf 'pwtest: %d pass, %d fail, %d skip\n' "$PWTEST_PASS" "$PWTEST_FAIL" "$PWTEST_SKIP" >&2
  [ "$PWTEST_FAIL" -eq 0 ]
}
# mutation crash-safety stack: newline-separated "file|backup" entries applied but not yet
# restored. The EXIT trap below replays them so a killed --mutation run cannot leave the tree
# mutated (two stuck mutations were the failure mode this guards).
PWTEST_MUT_STACK=""
_pwt_mutable_push() { PWTEST_MUT_STACK="${PWTEST_MUT_STACK:+$PWTEST_MUT_STACK
}$1"; }
_pwt_mutable_pop() {
  local e
  while IFS= read -r e; do
    [ "$e" = "$1" ] && continue
    PWTEST_MUT_STACK="${PWTEST_MUT_STACK:+$PWTEST_MUT_STACK
}$e"
  done <<<"$PWTEST_MUT_STACK"
}
_pwtest_cleanup() {
  local e
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    { _pwt_mutable_restore "$e"; } 2>/dev/null || true
  done <<<"${PWTEST_MUT_STACK:-}"
  PWTEST_MUT_STACK=""
  [ -n "${PWTEST_ROOT:-}" ] && [ -d "$PWTEST_ROOT" ] && rm -rf "$PWTEST_ROOT"; return 0
}
_pwt_mutable_restore() { local f="${1%%|*}" o="${1#*|}"; [ -f "$o" ] && cp "$o" "$f"; rm -f "$o"; return 0; }

# --- env --------------------------------------------------------------------
pwtest_env_init() {
  PWTEST_ROOT="$1"; ROOT="$PWTEST_ROOT"; export ROOT; mkdir -p "$PWTEST_ROOT/projects" "$PWTEST_ROOT/repos" "$PWTEST_ROOT/seeds"
  export PW_PROJECTS_DIR="$PWTEST_ROOT/projects" PW_REPOS="$PWTEST_ROOT/repos"
  export PWTEST_FORGE_STATE_FILE="$PWTEST_ROOT/forge-state"
  : > "$PWTEST_FORGE_STATE_FILE"
  export PWTEST_FORGE_LOG="$PWTEST_ROOT/forge.log"; : > "$PWTEST_FORGE_LOG"
  PWTEST_ORIG_PATH="$PATH"; export PWTEST_ORIG_PATH
  export PATH="$PWTEST_TESTSDIR/bin:$PATH"     # fake CLIs win over the machine's
}
pwtest_mkrow() { printf '%s|%s\n' "$1" "$2"; }

# --- git sandbox ---------------------------------------------------------------
pwtest_repo() {   # <name> [branch:<br>]… — create-once seed, clone, idempotent branch add
  local name="$1"; shift
  local seed="$PWTEST_ROOT/seeds/$name.git" work="$PW_REPOS/$name" spec br
  if [ ! -d "$work/.git" ]; then
    git init -q --bare "$seed" 2>/dev/null
    git clone -q "$seed" "$work" 2>/dev/null
    ( cd "$work"
      git checkout -q -b master 2>/dev/null || true
      echo "# seed" > seed.txt; git add -A
      git -c user.email=t@t -c user.name=t commit -qm init 2>/dev/null
      # Forge-plausible origin (mr-state/monitor resolve gitlab-vs-github from the origin URL;
      # `file://.../api.git` yields nothing); pushes re-route to the bare seed via insteadOf —
      # no network is ever contacted.
      git remote set-url origin    "https://gitlab.example.com/pwtest/$name.git"
      git remote set-url --push origin "$seed"
      git push -q -u origin master ) >/dev/null 2>&1
  fi
  for spec in "$@"; do
    case "$spec" in
      branch:*) br="${spec#branch:}"
        git -C "$work" show-ref -q --verify "refs/heads/$br" && continue
        ( cd "$work"; git show-ref -q --verify "refs/heads/master" || git symbolic-ref HEAD refs/heads/master; git checkout -q -b "$br" master
          echo "work for $br" > "file-$(printf '%s' "$br" | tr '/' '-')-$(date +%s).txt"; git add -A
          git -c user.email=t@t -c user.name=t commit -qm "branch $br"
          git push -q origin "$br"; git checkout -q master ) >/dev/null 2>&1 ;;
    esac
  done
}

# --- F1: verbatim scaffold -----------------------------------------------------
pwtest_build_f1() {
  local slug="$1"
  PW_PROJECTS="$PW_PROJECTS_DIR" PW_REPOS="$PW_REPOS" \
    "$PWTEST_TOOLING_DIR/scaffold.sh" "$slug" >/dev/null 2>&1
  printf '%s/%s' "$PW_PROJECTS_DIR" "$slug"
}

# --- fill a task file from the project-local template ---------------------------
# pwtest_fill_task <projdir> <Tn> <ststat> <mr> [title] [repo] [base]
pwtest_fill_task() {
  local p="$1" t="$2" stat="$3" mr="$4" title="${5:-do the thing}" repo="${6:-api}" base="${7:-master}" out
  out="$p/task/$t.md"; [ -f "$out" ] && return 0
  sed \
    -e "1s|.*|# $t: $title|" \
    -e "s|^- \*\*Repo:\*\* <repo>|- **Repo:** $repo|" \
    -e "s|^- \*\*Base branch:\*\* <branch>|- **Base branch:** $base|" \
    -e "s|^- \*\*Branch:\*\* .*\`|- **Branch:** \`agent/$(basename "$p")/$t-thing\`|" \
    -e "s|^- \*\*Worktree:\*\* .*\`|- **Worktree:** \`worktree/$repo/$t-thing/\`|" \
    -e "s|^- \*\*depends_on:\*\* <T-ids or none>|- **depends_on:** none|" \
    -e "s|^- \*\*Parallel group:\*\* <Gn or none>|- **Parallel group:** G1|" \
    -e "s|^- \*\*Landing unit:\*\* <short-name or none>|- **Landing unit:** none|" \
    -e "s|^- \*\*Status:\*\* todo .*|- **Status:** $stat|" \
    -e "s|^- \*\*Execute with:\*\* <provider:model-or-agent>|- **Execute with:** kilotest/test-model|" \
    -e "s|^- \*\*Why:\*\* <one line.*|- **Why:** fixture|" \
    -e "s|^- \*\*Story points:\*\* <n>|- **Story points:** 1|" \
    -e "s|^- \*\*Actually used:\*\* <.*|- **Actually used:** kilotest/test-model|" \
    -e "s|^- \*\*MR:\*\* <url.*|- **MR:** $mr|" \
    -e "s|^- \*\*Commit(s):\*\* <.*|- **Commit(s):** —|" \
    -e "s|^- \*\*Verify outcome:\*\* <pass.*|- **Verify outcome:** pass|" \
    -e "s|^- \*\*Build check:\*\* <.*|- **Build check:** —|" \
    "$p/task/_TEMPLATE-task.md" > "$out"
}

# review files: approve = latest plain row in Sign-off = approved (gate col-3 read, C5)
pwtest_approve_review() {
  local f="$1/$2"; [ -f "$f" ] || return 0
  awk 'BEGIN{done=0}
       /^\|[ ]*Date-time[^|]*\|[^|]*\|[ ]*Decision[^|]*\|/ { print; getline; print; print "| 2026-09-15 00:00 | pwtest | approved |"; done=1
         # swallow the default empty/in-review row that follows the header
         if ((getline nxt) > 0) { if (nxt !~ /^[|][ ]*[|]/) print nxt }
         next }
       done==0 && /^[|][ ]*[|][ ]*[|][ ]*in-review[ ]*\|[ ]*$/ { next }   # replace the template default
       { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# --- F2: mid-lifecycle, current baseline ----------------------------------------
pwtest_scaffold_into() {
  PW_PROJECTS="$PW_PROJECTS_DIR" PW_REPOS="$PW_REPOS" \
    "$PWTEST_TOOLING_DIR/scaffold.sh" "$1" >/dev/null 2>&1
}

pwtest_build_f2() {
  local slug="$1" p
  pwtest_scaffold_into "$slug"
  p="$PW_PROJECTS_DIR/$slug"; [ -d "$p" ] || return 1
  pwtest_repo api "branch:agent/$slug/T01-thing" "branch:agent/$slug/T02-thing" "branch:agent/$slug/T03-thing" "branch:agent/$slug/T04-thing"
  # T02 carries a (fake) MR; T03 exists for ship/verify states; T01 is shippable.
  pwtest_fill_task "$p" T01 done        "-" "Fix api's retry shim"
  pwtest_fill_task "$p" T02 done        "https://gitlab.example.com/pwtest/api/-/merge_requests/42" "Add rate limiter"
  pwtest_fill_task "$p" T03 in-progress "-" "Harden the sentinel path"
  # T04 = verify-FAILED, kept on purpose (gate must see verify-failed state):
  pwtest_fill_task "$p" T04 verify-failed "-" "Audit legacy flags"
  # analysis doc + three review files (PLAN + one task = open)
  mkdir -p "$p/analysis/review" "$p/task/review" "$p/rfc"
  local at="$p/analysis/_TEMPLATE.md"
  cp "$at" "$p/analysis/fixture.md"
  grep -q 'Author' "$p/analysis/fixture.md" || printf -- '\n- **Author:** pwtest\n' >> "$p/analysis/fixture.md"
  cp "$p/_REVIEW.template.md" "$p/analysis/review/fixture.review.md"
  cp "$p/_REVIEW.template.md" "$p/task/review/PLAN.review.md"
  cp "$p/_REVIEW.template.md" "$p/task/review/T04.review.md"
  pwtest_approve_review "$p" analysis/review/fixture.review.md
  pwtest_approve_review "$p" task/review/PLAN.review.md
  "$PWTEST_TOOLING_DIR/pw-lib.sh" status "$slug" executing >/dev/null 2>&1 \
    || sed -i '' 's/^- \*\*Status:\*\* context/- **Status:** executing/' "$p/README.md"
  "$PWTEST_TOOLING_DIR/pw-lib.sh" log "$slug" test "fixture materialized" >/dev/null 2>&1 || true
  # mount the worktrees each task declares (mr-state/pw-lib resolve the repo via the task's
  # Worktree:/Branch: fields, so those must point at actually-mounted worktrees).
  local tt
  for tt in T01 T02 T03 T04; do
    mkdir -p "$p/worktree/api"
    git -C "$PW_REPOS/api" worktree add "$p/worktree/api/$tt-thing" "agent/$slug/$tt-thing" >/dev/null 2>&1 || true
  done
  # PLAN: template copy with its sample rows replaced by real task rows (C4: the
  # CURRENT template rows already use markdown-linked IDs — F2 keeps them.)
  cp "$p/task/_TEMPLATE-orchestration-plan.md" "$p/task/PLAN.md"
  python3 - "$p/task/PLAN.md" "$slug" <<'PLANEOF'
import re,sys
f,slug=sys.argv[1],sys.argv[2]
t=open(f).read()
rows = ("| ID | Title | Repo | depends_on | Group | Execute with | SP | Status | Time | Result |\n"
        "|----|-------|------|------------|-------|--------------|----|--------|------|--------|\n"
        "| [T01](./T01.md) | Fix api's retry shim | api | — | G1 | kilotest/test-model | 1 | done | — | — |\n"
        "| [T02](./T02.md) | Add rate limiter | api | T01 | G1 | kilotest/test-model | 3 | done | — | !42 |\n"
        "| [T03](./T03.md) | Harden the sentinel path | api | T02 | G1 | kilotest/test-model | 2 | in-progress | — | — |\n"
        "| [T04](./T04.md) | Audit legacy flags | api | T03 | G1 | kilotest/test-model | 1 | verify-failed | — | — |\n")
hdr=re.search(r'^\| ID \| Title \|.*\n\|[-| ]+\n', t, re.M)
if hdr:
    # eat old data rows directly below the header
    tail = re.match(r'(?:\|[^\n]*\n?)+', t[hdr.end():])
    t = t[:hdr.start()] + rows + t[(hdr.end()+tail.end()) if tail else hdr.end():]
t = (t.replace("<project-slug>", slug).replace("<provider>", "kilotest")
       .replace("<YYYY-MM-DD HH:MM>", "2026-09-15 00:00")
       .replace("<link to analysis/*.md that is approved>", "[fixture](../analysis/fixture.md)")
       .replace("api-service","api").replace("hera","api").replace("valas","api").replace("spring3","master"))
t = re.sub(r'^- \*\*Status:\*\* [^\n]*', '- **Status:** approved-for-execution', t, flags=re.M, count=1)
open(f,"w").write(t)
PLANEOF
  sed -i '' "s@^- \*\*One-liner:\*\*.*@- **One-liner:** fixture project for the harness@" "$p/README.md" && rm -f "$p/README.md.bak"
    sed -i '' "s@\*\*Chosen approach:\*\* .*@**Chosen approach:** Option A — fixture choice@" "$p/analysis/fixture.md"
  # seed the dashboard from task truth — the SAME script does it, so "stale on arrival" can't bias tests:
  "$TOOL_DIR/pw-doc-sync.sh" "$slug" --dashboard-only >/dev/null 2>&1 \
    || python3 "$PWTEST_TOOLING_DIR/pw-doc-sync.py" --tooling "$PWTEST_TOOLING_DIR" "$slug" --dashboard-only >/dev/null 2>&1 || true
  printf '%s' "$p"
}

# --- F3: same recipe + adversarial data shapes (P1-derived edits, no era copies) --
pwtest_build_f3() {
  local slug="$1" src dst
  src="${PWTEST_F2:-}"; [ -n "$src" ] && [ -d "$src" ] || { echo "pwtest: f3 needs PWTEST_F2" >&2; return 1; }
  dst="$PW_PROJECTS_DIR/$slug"; rm -rf "$dst"; cp -a "$src" "$dst"
  local s2; s2="$(basename "$src")"
  for tsk in T01 T02 T03 T04; do
    sed -i \'\' "s|agent/$s2/|agent/$slug/|g" "$dst/task/$tsk.md"
    pwtest_repo api "branch:agent/$slug/$tsk-thing"
  done
  # C17: guidance prose copied INTO values (the exact class §13 killed):
  sed -i \'\' "s|^- \*\*Base branch:\*\* master\$|- **Base branch:** master (already cloned by you)|" "$dst/task/T03.md"
  sed -i \'\' "s|^- \*\*Execute with:\*\* .*|- **Execute with:** e.g. claude:sonnet, kilotest/test-model|" "$dst/task/T03.md"
  # linked MR cell (C4 shape rides inside Result value):
  sed -i \'\' "s|- \*\*MR:\*\* https://gitlab.example.com/pwtest/api/-/merge_requests/42$|- **MR:** [MR 42](https://gitlab.example.com/pwtest/api/-/merge_requests/42)|" "$dst/task/T02.md"
  # decoy (C21/C6): Steps contains a literal placeholder URL with NO Result MR line:
  cp "$dst/task/T03.md" "$dst/task/T05.md"
  sed -i \'\' "1s|.*|# T05: A \"quoted\" name's pass|" "$dst/task/T05.md"
  sed -i \'\' "s|^- \*\*MR:\*\* .*$|- **MR:** —|" "$dst/task/T05.md"
  awk '/^## Steps/{print "- See the template at https://gitlab.example.com/pwtest/api/-/merge_requests/000-stencil (placeholder)"; print; next} {print}' "$dst/task/T05.md" > "$dst/task/T05.a" && mv "$dst/task/T05.a" "$dst/task/T05.md"
  # (none)-sentinel + zero-change + CRLF (T06) + C1 lint-negative (built from the LOCAL
  # template with Repo/Story fields REMOVED — "unparseable-ish but valid" hostile shape):
  cp "$dst/task/_TEMPLATE-task.md" "$dst/task/T06.md"
  sed -i '' -e "1s@.*@# T06: zero-change shape@" \
             -e "s@^- \*\*Status:\*\* todo .*@- **Status:** todo@" \
             -e "s@^- \*\*MR:\*\* <url.*@- **MR:** (none); the MR is not needed for this task@" \
             -e "s@^- \*\*Commit(s):\*\* <.*@- **Commit(s):** zero-change@" \
             -e "/^- \*\*Repo:\*\*/d" -e "/^- \*\*Story points:\*\*/d" "$dst/task/T06.md"
  rm -f "$dst/task/T06.md.bak"
  awk '{printf "%s\r\n",$0}' "$dst/task/T06.md" > "$dst/task/T06.a" && mv "$dst/task/T06.a" "$dst/task/T06.md"
  # T05 carries the Steps-only decoy URL and NO Result MR field (must resolve EMPTY):
  cp "$dst/task/T04.md" "$dst/task/T05.md"
  sed -i '' -e "1s@.*@# T05: A \"quoted\" name's pass@" \
             -e "/^- \*\*MR:\*\*/d" "$dst/task/T05.md"
  rm -f "$dst/task/T05.md.bak"
  awk '/^## Steps/{print "- Decoy: see https://gitlab.example.com/pwtest/api/-/merge_requests/000-stencil for context"; print; next} {print}' "$dst/task/T05.md" > "$dst/task/T05.a" && mv "$dst/task/T05.a" "$dst/task/T05.md"
  # PLAN: one plain id, one linked + T05/T06 rows:
  python3 - "$dst/task/PLAN.md" <<'PY'
import re,sys
f=sys.argv[1]; t=open(f).read()
t=t.replace("| [T01](./T01.md) |","| T01 |")
extra=("| T05 | A \"quoted\" name's pass | api | — | G1 | kilotest/test-model | 1 | todo | — | — |\n"
       "| [T06](./T06.md) | zero-change shape | api | T03 | G1 | kilotest/test-model | 1 | todo | — | zero-change |\n")
m=re.search(r'\[?\| \[?T04][^\[]*[^\n]*\n', t)
open(f,"w").write(t + extra if not m else t)
PY
  [ -f "$dst/task/PLAN.md" ] && ! grep -q '^| T05 ' "$dst/task/PLAN.md" && printf '| T05 | A "quoted" name''s pass | api | — | G1 | kilotest/test-model | 1 | todo | — | — |\n| [T06](./T06.md) | zero-change shape | api | T03 | G1 | kilotest/test-model | 1 | todo | — | zero-change |\n' >> "$dst/task/PLAN.md"
  # local _TEMPLATE copies drift the other way (C20): refresh only project-local
  cp "$PWTEST_TEMPLATE_DIR/task/_TEMPLATE-task.md" "$dst/task/_TEMPLATE-task.md"
  # C19: prose-only phase line + legend word inside prose:
  sed -i \'\' "s|^- \*\*Status:\*\* [a-z-]*$|- **Status:** executed — 4/4 done (verify ✓) awaiting acceptance|" "$dst/README.md"
  printf '\nThe dashboard may flip to `verify-failed` later if CI regresses (prose mention, not a field).\n' >> "$dst/README.md"
  # dashboard task table: hand notes + a linked MR cell the rebuild must keep:
  python3 - "$dst/README.md" "$slug" <<'PY'
import sys,re
f=sys.argv[1]; t=open(f).read()
t=re.sub(r'^- \*\*One-liner:\*\* .*', '- **One-liner:** fixture (hostile shapes)', t, flags=re.M, count=1)
open(f,"w").write(t)
PY
  printf '%s' "$dst"
}

# --- lazy materialization (plan 19 F1): build only the fixtures the SELECTED scripts consume.
# static.sh (T0/T4) and corpus.sh (T3) never reference fixtures; a T1 `--only` child that runs
# one case clones only that case's fixture. Overbuild is safe (slower); underbuild fails loudly
# (cases error on missing dirs) — the scan errs toward matching, incl. comments.
NEED_F1=0; NEED_F2=0; NEED_F3=0
_pwtest_scan() { # <file>… — mark fixtures whose F/S vars the files reference
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    grep -qE '\$\{?[FS]1\}?|PWTEST_F1' "$f" && NEED_F1=1
    grep -qE '\$\{?[FS]2\}?|PWTEST_F2' "$f" && NEED_F2=1
    grep -qE '\$\{?[FS]3\}?|PWTEST_F3' "$f" && NEED_F3=1
  done
  [ "$NEED_F3" = 1 ] && NEED_F2=1     # F3 is derived from F2 (pwtest_build_f3 needs PWTEST_F2)
  return 0
}
# --- pristine fixture cache (plan 19 F2): when PWTEST_FIXTURE_CACHE is set, children copy
# cached fixtures instead of building. Cache key = the fixture RECIPE (template/ tree +
# scaffold.sh + pw-env.sh + pw_test_lib.sh) — NOT the runtime scripts. Convention this
# encodes: a mutation catcher must never depend on the mutation changing fixture BYTES
# (catchers test runtime readers on template-derived data; see docs/testing.md).
# Stored only by a run that built all three (warm/full); partial runs only read.
_pwtest_recipe_hash() {
  python3 - "$PW_HOME" <<'PY'
import hashlib, os, sys
root = sys.argv[1]; h = hashlib.sha256()
for base in ("template",):
    for dp, _, fns in sorted(os.walk(os.path.join(root, base))):
        for fn in sorted(fns):
            p = os.path.join(dp, fn)
            h.update(os.path.relpath(p, root).encode()); h.update(open(p, "rb").read())
for f in ("tooling/scaffold.sh", "tooling/pw-env.sh", "tooling/tests/pw_test_lib.sh"):
    p = os.path.join(root, f)
    if os.path.exists(p): h.update(f.encode()); h.update(open(p, "rb").read())
print(h.hexdigest()[:16])
PY
}
_pwtest_cache_dir() { # echoes $CACHE/<hash> when the cache is enabled; rc 1 otherwise
  [ -n "${PWTEST_FIXTURE_CACHE:-}" ] || return 1
  printf '%s/%s' "$PWTEST_FIXTURE_CACHE" "$(_pwtest_recipe_hash)"
}
_pwtest_cache_restore_root() { # repos+seeds once per run; rc 0 when root now present
  local cd="$1"
  [ -e "$PW_REPOS/api" ] && return 0
  [ -d "$cd/repos" ] || return 1
  mkdir -p "$PW_REPOS" "$PWTEST_ROOT/seeds"
  cp -a "$cd/repos/." "$PW_REPOS/" && cp -a "$cd/seeds/." "$PWTEST_ROOT/seeds/"
}
_pwtest_cache_repair() { # re-point F2's worktrees + clone push-URLs at THIS root (paths are absolute inside git metadata)
  local r wt
  for r in "$PW_REPOS"/*; do
    [ -d "$r/.git" ] || continue
    git -C "$r" remote set-url --push origin "$PWTEST_ROOT/seeds/$(basename "$r").git" >/dev/null 2>&1 || true
    for wt in "$PW_PROJECTS_DIR/$S2/worktree/$(basename "$r")/"*; do
      [ -d "$wt" ] || continue
      git -C "$r" worktree repair "$wt" >/dev/null 2>&1 || true
    done
  done
}
_pwtest_cache_store() { # all three built fresh → publish atomically (tmp dir + mv)
  local cd tmp s
  cd="$(_pwtest_cache_dir)" || return 0
  [ -e "$cd" ] && return 0
  for s in "$S1" "$S2" "$S3"; do [ -d "$PW_PROJECTS_DIR/$s" ] || return 0; done
  tmp="$cd.tmp.$$"; mkdir -p "$tmp/projects" "$tmp/repos" "$tmp/seeds"
  for s in "$S1" "$S2" "$S3"; do cp -a "$PW_PROJECTS_DIR/$s" "$tmp/projects/" && : > "$tmp/.done-$s" || { rm -rf "$tmp"; return 0; }; done
  cp -a "$PW_REPOS/." "$tmp/repos/" && cp -a "$PWTEST_ROOT/seeds/." "$tmp/seeds/" || { rm -rf "$tmp"; return 0; }
  mv "$tmp" "$cd" 2>/dev/null || rm -rf "$tmp"
  return 0
}
_pwtest_materialize() { # restore cached fixtures, build what is still missing, store if all built fresh
  local built="" hit="" _cd=""
  # A long-lived parent exports F1..F3/PWTEST_F2; a fresh child must never mistake an
  # inherited path for a fixture materialized in ITS OWN root (the lazy-build guard reads
  # these vars) — clear first, then restore-or-build per NEED_F*.
  F1=""; F2=""; F3=""; PWTEST_F2=""
  [ -n "${PWTEST_FIXTURE_CACHE:-}" ] && _cd="$(_pwtest_cache_dir)"
  if [ -n "$_cd" ] && [ "$NEED_F1" = 1 ] && [ -f "$_cd/.done-$S1" ]; then
    cp -a "$_cd/projects/$S1" "$PW_PROJECTS_DIR/" && { F1="$PW_PROJECTS_DIR/$S1"; export F1; hit="$hit F1"; }
  fi
  if [ -n "$_cd" ] && [ "$NEED_F2" = 1 ] && [ -f "$_cd/.done-$S2" ] && _pwtest_cache_restore_root "$_cd"; then
    cp -a "$_cd/projects/$S2" "$PW_PROJECTS_DIR/" && { _pwtest_cache_repair; F2="$PW_PROJECTS_DIR/$S2"; export F2 PWTEST_F2="$F2"; hit="$hit F2"; }
  fi
  if [ -n "$_cd" ] && [ "$NEED_F3" = 1 ] && [ -f "$_cd/.done-$S3" ] && _pwtest_cache_restore_root "$_cd"; then
    cp -a "$_cd/projects/$S3" "$PW_PROJECTS_DIR/" && { F3="$PW_PROJECTS_DIR/$S3"; export F3; hit="$hit F3"; }
  fi
  if { [ "$NEED_F1" = 1 ] && [ -z "${F1:-}" ]; } || { [ "$NEED_F2" = 1 ] && [ -z "${F2:-}" ]; } || { [ "$NEED_F3" = 1 ] && [ -z "${F3:-}" ]; }; then
    echo "TEST materializing fixtures from template/ …" >&2
    if [ "$NEED_F1" = 1 ] && [ -z "${F1:-}" ]; then F1="$(pwtest_build_f1 "$S1")" || { echo "pwtest: F1 build failed" >&2; exit 2; }; export F1; built="$built F1"; fi
    if [ "$NEED_F2" = 1 ] && [ -z "${F2:-}" ]; then F2="$(pwtest_build_f2 "$S2")" || { echo "pwtest: F2 build failed" >&2; exit 2; }; export F2 PWTEST_F2="$F2"; built="$built F2"; fi
    if [ "$NEED_F3" = 1 ] && [ -z "${F3:-}" ]; then F3="$(pwtest_build_f3 "$S3")" || { echo "pwtest: F3 build failed" >&2; exit 2; }; export F3; built="$built F3"; fi
    _pwtest_cache_store
  fi
  printf 'TEST fixtures built:%s\n' "${built:- none}" >&2
  [ -n "$hit" ] && printf 'TEST fixtures cache-hit:%s\n' "$hit" >&2
  return 0
}
