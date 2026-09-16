# shellcheck shell=bash
# static.sh — T0 (syntax/help/forbidden-idiom greps) and T4 (consistency & canaries).
# Every forbidden pattern here encodes a bug that actually shipped once (plan 16 §5).

# the 14 automation scripts (single list; T0/T1/T2/mutation reuse it)
PWTEST_AUTOMATION="pw-status.sh pw-preflight.sh pw-review-scan.sh pw-doc-lint.sh pw-doc-summary.sh pw-doc-sync.sh pw-ship-resolve.sh pw-mr-state-batch.sh pw-rfc-comments.sh pw-context-fetch.sh pw-adopt-snapshot.sh pw-worktree-create.sh pw-ship-exec.sh pw-pipeline-monitor.sh"
export PWTEST_AUTOMATION

_pwtest_code_lines() { awk '!/^[[:space:]]*#/' "$@" 2>/dev/null | cat -n; }

static_t0() {
  echo "== T0 static ==" >&2
  local f code hits re label excl

  # 1) syntax — every shell file in tooling/ and the suite itself
  for f in "$TOOL"/*.sh "$TOOL"/tests/pw_test*.sh "$TOOL"/tests/static.sh "$TOOL"/tests/battery.sh "$TOOL"/tests/corpus.sh "$TOOL"/tests/mutate.sh "$TOOL"/tests/bin/gh; do
    [ -f "$f" ] && { bash -n "$f" && pwtest_ok "bash -n ${f#$TOOL/}" || pwtest_bad "bash -n ${f#$TOOL/}" "syntax error"; }
  done

  # 2) every automation script takes --help (or is listed in known-nohelp.allow)
  for f in $PWTEST_AUTOMATION; do
    if PW_PROJECTS_DIR="$PWTEST_ROOT/projects" "$TOOL/$f" --help >"$ROOT/h.out" 2>&1; then
      grep -qiE 'usage|how to|options|[A-Za-z-]+ +<' "$ROOT/h.out" && pwtest_ok "$f --help prints usage" \
        || pwtest_bad "$f --help prints usage" "exit 0 but no usage text"
    else
      pwtest_bad "$f --help" "non-zero rc=$?"
    fi
  done

  # 3) forbidden idioms (code lines only; comments may *warn* about them).
  # TAB-delimited columns: re, excl, label (patterns contain literal "|").
  code="$(_pwtest_code_lines "$TOOL"/pw-*.sh "$TOOL"/scaffold.sh "$TOOL"/pw-doctor.sh)"
  while IFS=$'	' read -r re excl label; do
    [ -z "$re" ] && continue
    hits="$(printf '%s\n' "$code" | grep -E -- "$re" || true)"
    [ -n "$excl" ] && [ "$excl" != '-' ] && hits="$(printf '%s\n' "$hits" | grep -vE -- "$excl" || true)"
    if [ -n "$hits" ]; then pwtest_bad "T0: $label" "found: $(printf '%s' "$hits" | head -2 | cut -c1-120 | tr '\n' ' ')"
    else pwtest_ok "T0: $label"; fi
  done <<'IDIOMS'
declare -A	-	bash-3.2 forbidden (C11)
\| *xargs	grep	no | xargs | trim idiom (C14)
grep -c .*\|\| echo 0	-	never the grep-c-||-echo-0 idiom
grep[^#]*verify-failed	- \*\*Status:|\|.*verify-failed.*\|	machine-token read must be field-anchored (C18)
^# Tasks|\^## Tasks	-	no bare `## Tasks` anchor literal (C2)
exec "\$0"	-	re-spawn via $HERE not $0 (C12)
bash "\$0"	-	re-spawn via $HERE not $0 (C12)
IDIOMS

      # 4) every script resolves projects from PW_PROJECTS_DIR (C16)
  for f in $PWTEST_AUTOMATION; do
    grep -q 'PW_PROJECTS_DIR' "$TOOL/$f" && pwtest_ok "T0: $f honors PW_PROJECTS_DIR" || pwtest_bad "T0: $f honors PW_PROJECTS_DIR" "hard-wired project root"
  done
}

static_t4() {
  echo "== T4 consistency & boundaries ==" >&2
  local n hits f

  # 1) providers in sync (doctor compares generated vs installed; run before any regen)
  # real PATH during the real-install check: the forge shims change `command -v` answers and
  # would make gen render differently than the installed copy.
  if env -u PWTEST_FORGE_STATE_FILE -u PW_PROJECTS_DIR -u PW_REPOS -u PW_PROJECTS PATH="$PWTEST_ORIG_PATH" "$TOOL/pw-doctor.sh" >"$ROOT/doctor.out" 2>&1; then pwtest_ok "T4 pw-doctor reports in sync"
  else pwtest_bad "T4 pw-doctor reports in sync" "fix: $TOOL/pw-doctor.sh --fix — $(grep -i 'out of sync\|drift\|missing' "$ROOT/doctor.out" | head -1)"; fi

  # 2) registry symmetry: index file == automation set; refs ⊆ known; every file wired
  local idx refs known allow
  idx="$(sed -n '/^## Index/,/^## /p' "$TOOL/docs/scripts/README.md" 2>/dev/null | grep -oE '`pw-[a-z0-9-]+\.sh`' | tr -d '`' | sort -u)"
  known="$(printf '%s\n' $PWTEST_AUTOMATION | sort -u)"
  if [ "$idx" = "$known" ]; then pwtest_ok "T4 docs/scripts index == the 14" ; else pwtest_bad "T4 docs/scripts index" "diff: $(comm -3 <(printf '%s\n' "$known") <(printf '%s\n' "$idx") | tr '\n' ' ')"; fi
  refs="$(grep -rhoE 'pw-[a-z-]+\.sh' "$TOOL/commands" "$TOOL/agents" "$TOOL/skill" | sort -u)"
  allow="$(awk -F'\t' '!/^#/ && $1 {print $1}' "$TOOL/tests/expectations/unwired.ok" 2>/dev/null | sort -u)"
  hits="$(comm -23 <(printf '%s\n' "$refs") <(printf '%s\n' "$known" "$allow" | sort -u) )"
  [ -z "$hits" ] && pwtest_ok "T4 entry paths reference only registry/allowlisted scripts" \
    || pwtest_bad "T4 entry paths reference known scripts" "$hits"
  local unreferenced="$(comm -13 <(printf '%s\n' "$refs" "$allow" | sort -u) <(printf '%s\n' "$known"))"
  [ -z "$unreferenced" ] && pwtest_ok "T4 every automation script wired to an entry path" \
    || pwtest_bad "T4 every automation script wired" "unreferenced: $(printf '%s' "$unreferenced" | tr '\n' ' ') $(printf '%s\n' "$unreferenced" | while read -r z; do grep -l "$z" "$TOOL"/commands/* >/dev/null 2>&1 && echo "(in commands)"; done)"

  # 3) information boundary — only the 14 names; pw-env.sh remains the allowed human ref
  hits=""
  for n in $PWTEST_AUTOMATION; do
    for f in "$TOOL/../README.md" "$TOOL/../AGENTS.md" "$TOOL/../CLAUDE.md" "$TOOL/../docs/"*.md; do
      [ -f "$f" ] && grep -qF "$n" "$f" && hits="$hits $n@$(basename "$f")"
    done
  done
  [ -z "$hits" ] && pwtest_ok "T4 user docs free of automation-script names" \
    || pwtest_bad "T4 user docs free of automation-script names" "$hits"
  hits=""
  for f in "$TOOL/../docs/"*.md "$TOOL"/commands/*.md "$TOOL"/agents/*.md "$TOOL"/skill/*/*.md "$TOOL"/skill/*/*/*.md; do
    [ -f "$f" ] && grep -qE '\b[Pp]lan[ .-]?[1-9][0-9]\b' "$f" && hits="$hits $f"
  done
  [ -z "$hits" ] && pwtest_ok "T4 no internal plan references in published files" \
    || pwtest_bad "T4 no internal plan references" "$hits"

  # 4) doctrine canaries
  # audience split (users: bundle-root AGENTS.md; maintainers: tooling/AGENTS.md + CLAUDE.md) —
  # the doctrine must live in the maintainer entry point, and the user entry point must point there.
  grep -qF 'single source of truth' "$TOOL/AGENTS.md" \
    && grep -qF 'tooling/AGENTS.md' "$TOOL/../AGENTS.md" && grep -qF '@AGENTS.md' "$TOOL/CLAUDE.md" \
    && pwtest_ok "T4 canary: sources-only doctrine in tooling/AGENTS.md + user pointer + tooling CLAUDE import" \
    || pwtest_bad "T4 canary: sources-only doctrine" "doctrine text missing from tooling/AGENTS.md, or the user entry-point pointer/tooling CLAUDE.md import died (C23: this exact rule dying cost a fixes round)"
  grep -qE '^- \*\*Status:\*\* context' "$TOOL/../template/PROJECT.template.md" \
    && grep -qE 'context → analysis → breakdown' "$TOOL/../template/PROJECT.template.md" \
    && pwtest_ok "T4 canary: phase machine line + vocabulary in template" \
    || pwtest_bad "T4 canary: phase machine line" "the README Status contract or its vocabulary comment was changed (C19 reads depend on it)"
  grep -qF 'FIELD-BULLET RULE' "$PWTEST_TEMPLATE_DIR/task/_TEMPLATE-task.md" && pwtest_ok "T4 canary: FIELD-BULLET rule in task template" \
    || pwtest_bad "T4 canary: FIELD-BULLET rule" "guidance-in-comments rule removed (C17)"
  grep -qF 'verify-failed' "$PWTEST_TEMPLATE_DIR/task/_TEMPLATE-task.md" && pwtest_ok "T4 canary: verify-failed token still documented in template" \
    || pwtest_bad "T4 canary: verify-failed token" "$(basename "$PWTEST_TEMPLATE_DIR") template lost it"
  # 5) shared plumbing used, not reinvented
  for f in $PWTEST_AUTOMATION; do
    grep -q 'pw-common\.sh' "$TOOL/$f" && pwtest_ok "T4: $f sources pw-common" || pwtest_bad "T4: $f sources pw-common" "P2 violation (readers re-implemented)"
  done
}
