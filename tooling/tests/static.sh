# shellcheck shell=bash
# static.sh — T0 (syntax/help/forbidden-idiom greps) and T4 (consistency & canaries).
# Every forbidden pattern here encodes a bug that actually shipped once (plan 16 §5).

# the automation-script registry (single list; T0/T1/T2/mutation reuse it)
PWTEST_AUTOMATION="pw-status.sh pw-preflight.sh pw-review-scan.sh pw-doc-lint.sh pw-doc-summary.sh pw-doc-sync.sh pw-ship-resolve.sh pw-mr-state-batch.sh pw-rfc-comments.sh pw-context-fetch.sh pw-adopt-snapshot.sh pw-worktree-create.sh pw-ship-exec.sh pw-pipeline-monitor.sh pw-review-edit.sh pw-context.sh"
export PWTEST_AUTOMATION

_pwtest_code_lines() { awk '!/^[[:space:]]*#/' "$@" 2>/dev/null | cat -n; }

static_t0() {
  echo "== T0 static ==" >&2
  local f code hits re label excl

  # 1) syntax — every shell file in tooling/ (incl. the scripts/ layout) and the suite itself
  for f in "$TOOL"/*.sh "$TOOL"/scripts/*/*.sh "$TOOL"/tests/pw_test*.sh "$TOOL"/tests/static.sh "$TOOL"/tests/battery.sh "$TOOL"/tests/corpus.sh "$TOOL"/tests/mutate.sh "$TOOL"/tests/bin/gh; do
    [ -f "$f" ] && { bash -n "$f" && pwtest_ok "bash -n ${f#$TOOL/}" || pwtest_bad "bash -n ${f#$TOOL/}" "syntax error"; }
  done

  # 2) every automation script takes --help (or is listed in known-nohelp.allow)
  for f in $PWTEST_AUTOMATION; do
    if PW_PROJECTS_DIR="$PWTEST_ROOT/projects" "$(pwtest_script "$f")" --help >"$ROOT/h.out" 2>&1; then
      grep -qiE 'usage|how to|options|[A-Za-z-]+ +<' "$ROOT/h.out" && pwtest_ok "$f --help prints usage" \
        || pwtest_bad "$f --help prints usage" "exit 0 but no usage text"
    else
      pwtest_bad "$f --help" "non-zero rc=$?"
    fi
  done

  # 3) forbidden idioms (code lines only; comments may *warn* about them).
  # TAB-delimited columns: re, excl, label (patterns contain literal "|").
  code="$(_pwtest_code_lines "$TOOL"/pw-lib.sh "$TOOL"/scripts/*/*.sh)"
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
    grep -q 'PW_PROJECTS_DIR' "$(pwtest_script "$f")" && pwtest_ok "T0: $f honors PW_PROJECTS_DIR" || pwtest_bad "T0: $f honors PW_PROJECTS_DIR" "hard-wired project root"
  done
}

static_t4() {
  echo "== T4 consistency & boundaries ==" >&2
  local n hits f

  # 1) providers in sync (doctor compares generated vs installed; run before any regen)
  # real PATH during the real-install check: the forge shims change `command -v` answers and
  # would make gen render differently than the installed copy.
  if env -u PWTEST_FORGE_STATE_FILE -u PW_PROJECTS_DIR -u PW_REPOS -u PW_PROJECTS PATH="$PWTEST_ORIG_PATH" "$(pwtest_script pw-doctor.sh)" >"$ROOT/doctor.out" 2>&1; then pwtest_ok "T4 pw-doctor reports in sync"
  else pwtest_bad "T4 pw-doctor reports in sync" "fix: $TOOL/pw-doctor.sh --fix — $(grep -i 'out of sync\|drift\|missing' "$ROOT/doctor.out" | head -1)"; fi

  # 2) registry symmetry: index file == automation set; refs ⊆ known; every file wired
  local idx refs known allow
  idx="$(sed -n '/^## Index/,/^## /p' "$TOOL/docs/scripts/README.md" 2>/dev/null | grep -oE '`pw-[a-z0-9-]+\.sh`' | tr -d '`' | sort -u)"
  known="$(printf '%s\n' $PWTEST_AUTOMATION | sort -u)"
  if [ "$idx" = "$known" ]; then pwtest_ok "T4 docs/scripts index == the automation registry" ; else pwtest_bad "T4 docs/scripts index == the automation registry" "diff: $(comm -3 <(printf '%s\n' "$known") <(printf '%s\n' "$idx") | tr '\n' ' ')"; fi
  refs="$(grep -rhoE 'pw-[a-z-]+\.sh' "$TOOL/commands" "$TOOL/agents" "$TOOL/skill" | sort -u)"
  allow="$(awk -F'\t' '!/^#/ && $1 {print $1}' "$TOOL/tests/expectations/unwired.ok" 2>/dev/null | sort -u)"
  hits="$(comm -23 <(printf '%s\n' "$refs") <(printf '%s\n' "$known" "$allow" | sort -u) )"
  [ -z "$hits" ] && pwtest_ok "T4 entry paths reference only registry/allowlisted scripts" \
    || pwtest_bad "T4 entry paths reference known scripts" "$hits"
  local unreferenced="$(comm -13 <(printf '%s\n' "$refs" "$allow" | sort -u) <(printf '%s\n' "$known"))"
  [ -z "$unreferenced" ] && pwtest_ok "T4 every automation script wired to an entry path" \
    || pwtest_bad "T4 every automation script wired" "unreferenced: $(printf '%s' "$unreferenced" | tr '\n' ' ') $(printf '%s\n' "$unreferenced" | while read -r z; do grep -l "$z" "$TOOL"/commands/* >/dev/null 2>&1 && echo "(in commands)"; done)"

  # 3) information boundary — only registry names; pw-env.sh remains the allowed human ref
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
  # plan-17 doc-authoring doctrine canaries:
  # (a) the signoff operator's C4 human-only doctrine line lives in the command file…
  grep -qF 'HUMAN-TRIGGERED ONLY' "$TOOL/commands/pw-review.md" \
    && pwtest_ok "T4 canary: signoff C4 doctrine line in pw-review.md" \
    || pwtest_bad "T4 canary: signoff C4 doctrine line" "pw-review.md lost the 'HUMAN-TRIGGERED ONLY' label on the signoff operator — the gate doctrine's only command-side guard"
  # (b) …and NO agent file may ever invoke it (anti-idiom: agent-side path is auto-signoff only)
  hits="$(grep -lE 'pw-review-edit\.sh signoff|review-edit\.sh.*signoff' "$TOOL"/agents/*.md 2>/dev/null | tr '\n' ' ')"
  [ -z "$hits" ] && pwtest_ok "T4 canary: no agent file invokes signoff" \
    || pwtest_bad "T4 canary: no agent file invokes signoff" "C4 violation in: $hits — only a human triggers a gate decision (agent path: pw-lib.sh review auto-signoff)"
  # (c) capability-placement conventions doc exists, is linked from the maintainer entry, and freezes pw-lib
  [ -f "$TOOL/docs/conventions.md" ] && grep -qF 'docs/conventions.md' "$TOOL/AGENTS.md" \
    && grep -qE '^# FROZEN \(S2' "$(pwtest_script pw-lib.sh)" \
    && pwtest_ok "T4 canary: conventions.md exists + linked + pw-lib S2 freeze note" \
    || pwtest_bad "T4 canary: conventions doc" "tooling/docs/conventions.md missing, or its tooling/AGENTS.md link died, or pw-lib.sh lost the S2 FROZEN header note"
  # (d) the new entity scripts keep their group-doc section (usage reference completeness)
  grep -qF 'pw-review-edit.sh' "$TOOL/docs/scripts/review-and-context-editing.md" \
    && grep -qF 'pw-context.sh' "$TOOL/docs/scripts/review-and-context-editing.md" \
    && pwtest_ok "T4 canary: review-and-context-editing group doc covers both scripts" \
    || pwtest_bad "T4 canary: group doc coverage" "docs/scripts/review-and-context-editing.md lost a script section — no doc-less capability ships"
  # (e) plan-19 harness mechanics documented — no speedup ships undocumented:
  grep -qF '## Inside the harness' "$TOOL/docs/testing.md" \
    && grep -qF '## Writing a mutation row' "$TOOL/docs/testing.md" \
    && grep -qF 'PWTEST_MUT_JOBS' "$TOOL/docs/testing.md" \
    && grep -qF 'PWTEST_MUT_TIMEOUT' "$TOOL/docs/testing.md" \
    && pwtest_ok "T4 canary: harness internals + env knobs + row-authoring documented" \
    || pwtest_bad "T4 canary: harness docs" "testing.md lost §Inside the harness / §Writing a mutation row or the PWTEST_MUT_* knob names"
  # 5) shared plumbing used, not reinvented
  for f in $PWTEST_AUTOMATION; do
    grep -q 'pw-common\.sh' "$(pwtest_script "$f")" && pwtest_ok "T4: $f sources pw-common" || pwtest_bad "T4: $f sources pw-common" "P2 violation (readers re-implemented)"
  done

  # 6) L-rules layout canaries (tooling/docs/conventions.md): no file ships outside its kind-dir,
  # no caller references a layout path it must not know, and the registry mirrors the tree.
  # (a) dead-path: zero flat tooling/<entry>.sh refs anywhere (pw-lib exempt until its dissolution)
  hits="$(grep -rlE 'tooling/(pw-[a-z0-9-]+|scaffold|gen-[a-z-]+)\.sh' "$TOOL/.." --include='*.sh' --include='*.md' 2>/dev/null \
    | grep -v '/pw-lib\.sh$' | while read -r f; do
        if grep -qE 'tooling/pw-lib\.sh' "$f"; then grep -qE 'tooling/(pw-[a-z0-9-]+|scaffold|gen-[a-z-]+)\.sh' <(sed 's#tooling/pw-lib\.sh#pwlib#g' "$f") && printf '%s ' "$f"; else printf '%s ' "$f"; fi
      done)"
  [ -z "$hits" ] && pwtest_ok "T4: no flat tooling/<script>.sh references (L5)" \
    || pwtest_bad "T4: no flat tooling/<script>.sh references (L5)" "stale refs in: $hits"
  # (b) registry == tree (non-registry entry points exempt per unwired.ok rationale)
  local ents
  ents="$(cd "$TOOL/scripts/entities" && ls | sort -u)"
  ents="$(awk 'NR==FNR{ex[$1];next} !($1 in ex)' "$TOOL/tests/expectations/unwired.ok" <(printf '%s\n' "$ents"))"
  known="$(printf '%s\n' $PWTEST_AUTOMATION | sort -u)"
  [ "$ents" = "$known" ] && pwtest_ok "T4: scripts/entities/ == the registry (L1)" \
    || pwtest_bad "T4: scripts/entities/ == registry" "$(comm -3 <(printf '%s\n' "$known") <(printf '%s\n' "$ents") | tr '\n' ' ')"
  # (c) libraries invisible to callers (L2)
  hits="$(grep -rl 'scripts/lib/' "$TOOL/commands" "$TOOL/agents" "$TOOL/skill" 2>/dev/null | tr '\n' ' ')"
  [ -z "$hits" ] && pwtest_ok "T4: no entry path references scripts/lib/ (L2)" \
    || pwtest_bad "T4: no entry path references scripts/lib/" "$hits"
  # (d) toolchain allowlist (L3): entry paths may name scripts/toolchain/ only per toolchain.ok
  local ok f2 pair hits2=""
  ok="$TOOL/tests/expectations/toolchain.ok"
  hits2="$(grep -rlE 'scripts/toolchain/[a-z-]+\.sh' "$TOOL/commands" "$TOOL/agents" "$TOOL/skill" 2>/dev/null | while read -r f2; do
      grep -ohE 'scripts/toolchain/[a-z-]+\.sh' "$f2" | sed "s|^|${f2#$TOOL/}\t|"
    done | sort -u)"
  known="$(grep -v '^#' "$ok" 2>/dev/null | sort -u)"
  [ -z "$(comm -23 <(printf '%s\n' "$hits2") <(printf '%s\n' "$known"))" ] \
    && pwtest_ok "T4: toolchain refs ⊆ allowlist (L3)" \
    || pwtest_bad "T4: toolchain refs ⊆ allowlist" "$(comm -23 <(printf '%s\n' "$hits2") <(printf '%s\n' "$known") | tr '\n' ' ') — L3: workflow entry paths may invoke toolchain scripts only per expectations/toolchain.ok"
}
