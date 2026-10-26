# shellcheck shell=bash
# static.sh — T0 (syntax/help/forbidden-idiom greps) and T4 (consistency & canaries).
# Every forbidden pattern here encodes a bug that actually shipped once (plan 16 §5).

# the automation-script registry (single list; T0/T1/T2/mutation reuse it)
PWTEST_AUTOMATION="pw-status.sh pw-preflight.sh pw-ship.sh pw-review.sh pw-review-read.sh pw-rfc.sh pw-worktree.sh pw-doc.sh pw-context.sh pw-config.sh pw-session.sh pw-help.sh pw-project-doctor.sh"
export PWTEST_AUTOMATION

_pwtest_code_lines() { awk '!/^[[:space:]]*#/' "$@" 2>/dev/null | cat -n; }

# _pwtest_namedarg_scan — plan 46 named-argument contract scanner. stdin: candidate lines in
# `<file>:<line>:<text>` form; stdout: offending lines. Bounded regexes ONLY (each encodes a
# pre-migration shape that actually shipped in docs/templates); the live-context class requires
# the command to sit at line start or right after ` $ > : (the -nH prefix) so prose mentions
# stay clean. Every class is fixture-tested by the T4 canary before it guards the live tree.
_pwtest_namedarg_scan() {
  local all R1 R1A R2 R3 R4 R5 R6 R7 R8 R8A
  all="$(cat)"
  R1='(^|[`$>:])/pw-(new|analyze|breakdown|close|sync|execute|status|ship|config|context|adopt|rfc|doctor|review) +[a-z0-9][a-z0-9-]*'
  R1A='pw-review (init|init-all|item|answer|signoff|prepare|import|ai|config|reopen|archive|passes|read|gate|count|has-open|resolve|reindex)\b|pw-(status|ship) (rewind|comments|request-review|stack|stack-adopt|update|draft|ready)\b|pw-config (global|model-check|model-resolve|show|get|set|ensure|ai-model|ai-review|review-trigger|review-repair|review-rounds|agent-model)\b|pw-context (adopt|add-input|add-repo|fetch|prepare|req-init|scan)\b|pw-rfc (init|target|state|comment-seen|dashboard|comments|milestone|deploy)\b|pw-adopt\b|/pw-[a-z-]+ (to|for|and|or|the|an|will|can|is|runs|works|already|side-loop|command|commands|before|after|twice|again|now|still|only|users?|sessions?|without|with)\b'
  R2='--project +[^ ]+ +(item|answer|signoff|prepare|import|ai|comments|request-review|rewind|set|ensure|global|adopt|milestone)\b'
  R3='pw-config(\.sh)? +(project|ai-review|ai-model|review-trigger|review-repair|review-rounds) +[a-z0-9<-]'
  R4='/(pw-review) +(item|answer) +([^ -][^ ]*/|<[a-z-]+>)'
  R5='/(pw-help) +(project|command|operators|find) +[a-z<]'
  R6='task IDs use spaces|[Mm]ultiple task IDs use spaces|task[- ]ids? separated by spaces'
  R7='<task-id>…'
  R8='pw-[a-z-]+\.sh [a-z][a-z0-9-]* +[a-z0-9<]'
  R8A='pw-ship\.sh stack adopt\b|pw-config\.sh global +show\b|\.sh [a-z][a-z0-9-]* (and|or|the|a|an|is|are|was|will|to|for|with|in|on|at|by)\b'
  {
    printf '%s\n' "$all" | grep -E -- "$R1" | grep -vE -- "$R1A" || true
    printf '%s\n' "$all" | grep -E -- "$R2" || true
    printf '%s\n' "$all" | grep -E -- "$R3" || true
    printf '%s\n' "$all" | grep -E -- "$R4" || true
    printf '%s\n' "$all" | grep -E -- "$R5" || true
    printf '%s\n' "$all" | grep -E -- "$R6" || true
    printf '%s\n' "$all" | grep -E -- "$R7" || true
    printf '%s\n' "$all" | grep -E -- "$R8" | grep -vE -- "$R8A" || true
  } | awk '!seen[$0]++'
}

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
  code="$(_pwtest_code_lines "$TOOL"/scripts/*/*.sh)"
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
pw_phase_hint \| sed	-	phase hint uses bash replacement, never a sed program splice (C234/C243 class)
s\|{{PW_HOME}}\|	-	help token substitution is bash replacement, not a sed program (S3 class)
\\Q{{PW_HOME}}\\E	-	perl token stamping replaced by pw_stamp_tokens — install paths stay data
s/<PROJECT_NAME>/	-	rfc/scaffold template stamping is bash replacement, not sed (S3 class)
'"\$	\$'	no shell variable spliced into an awk program (S20 class)
\$[A-Za-z_]+\.tmp"	\$work	fixed-name staging is banned — pw_tmpfile + mv (S7 class)
\.pwrev\.\$	-	review staging is mktemp-only, never a fixed .pwrev name (S7 class)
\.pwtmp\.\$\$	pw_tmpfile\(\)	no PID-fallback staging names — mktemp or die (pw_tmpfile's own fallback excepted)
\.pwguidance\.	-	guidance rewrites stage via pw_tmpfile (S7 class)
\.(dash|fill|plan)-err	\$work	err side-files via mktemp, never a fixed suffixed name (S7 class)
IDIOMS

      # 4) every script resolves projects from PW_PROJECTS_DIR (C16)
  for f in $PWTEST_AUTOMATION; do
    grep -q 'PW_PROJECTS_DIR' "$(pwtest_script "$f")" && pwtest_ok "T0: $f honors PW_PROJECTS_DIR" || pwtest_bad "T0: $f honors PW_PROJECTS_DIR" "hard-wired project root"
  done
}

static_t4() {
  echo "== T4 consistency & boundaries ==" >&2
  local n hits f hintline

  # 0) fix hints are user-command-only (plan 27 F1; rev i widened; plan 30 widened to ALL entities):
  # hint/decision literals in EVERY entity script — echo/→fix lines, die_fix remediations, and the
  # add_error texts pw-doc.sh embeds — must name /pw-* commands or the human-owned pw.config.sh,
  # never raw scripts ($CFG expansions, tool script names). Comments stay exempt (maintainer prose);
  # usage strings without a → fix are the script's own --help surface (agent-facing) and are exempt.
  hintline="$(awk '!/^[[:space:]]*#/' "$TOOL"/scripts/entities/*.sh \
    | grep -E '→ (fix|decision)|die_fix|add_error|PHASE_FIX=' \
    | grep -E 'pw-[a-z-]*\.sh|\$CFG|\$\{CFG\}|scaffold\.sh' || true)"
  if [ -z "$hintline" ]; then pwtest_ok "T4 canary: entity fix hints are script-free (plan 30: all entities)"
  else pwtest_bad "T4 canary: entity fix hints are script-free" "$(printf '%s' "$hintline" | grep . | head -2 | cut -c1-110 | tr '\n' '|')"; fi

  # 1) providers in sync (doctor compares generated vs installed; run before any regen)
  # real PATH during the real-install check: the forge shims change `command -v` answers and
  # would make gen render differently than the installed copy.
  if [ "${PWTEST_INNER:-}" = 1 ] && [ ! -d "$TOOL/../.git" ]; then
    # A disposable copy is not installed anywhere: the provider bodies under $HOME are
    # stamped with the SOURCE PW_HOME, so they can never match this copy. The check is
    # about the installed state of a real tree, and a red verdict here would make every
    # sweep child fail for a reason no mutation caused.
    pwtest_ok "T4 pw-doctor in-sync check skipped (disposable copy, not installed anywhere)"
  elif [ -f "$TOOL/../.git" ]; then
    # A git worktree is a development copy, never the installed source; its stamped paths cannot
    # match the provider artifacts. The real installed tree (a .git DIRECTORY) runs the check.
    pwtest_ok "T4 pw-doctor in-sync check skipped (development worktree)"
  elif [ ! -f "$TOOL/../pw-env.sh" ] || ! grep -qF "export PW_HOME=\"$TOOL/..\"" "$TOOL/../pw-env.sh"; then
    # A worktree or uninstalled export is not the provider's install source: its stamped paths
    # can never match. This check belongs to the tree that actually owns the installed artifacts.
    pwtest_ok "T4 pw-doctor in-sync check skipped (bundle tree is not the installed source)"
  elif env -u PWTEST_FORGE_STATE_FILE -u PW_PROJECTS_DIR -u PW_REPOS -u PW_PROJECTS PATH="$PWTEST_ORIG_PATH" "$(pwtest_script pw-doctor.sh)" >"$ROOT/doctor.out" 2>&1; then pwtest_ok "T4 pw-doctor reports in sync"
  else pwtest_bad "T4 pw-doctor reports in sync" "fix: $TOOL/pw-doctor.sh --fix — $(grep -i 'out of sync\|drift\|missing' "$ROOT/doctor.out" | head -1)"; fi

  # 2) registry symmetry: index file == automation set; refs ⊆ known; every file wired
  local idx refs known allow
  idx="$(sed -n '/^## Index/,/^## /p' "$TOOL/docs/scripts/README.md" 2>/dev/null | grep -oE '`pw-[a-z0-9-]+\.sh`' | tr -d '`' | sort -u)"
  known="$(printf '%s\n' $PWTEST_AUTOMATION | sort -u)"
  if [ "$idx" = "$known" ]; then pwtest_ok "T4 docs/scripts index == the automation registry" ; else pwtest_bad "T4 docs/scripts index == the automation registry" "diff: $(comm -3 <(printf '%s\n' "$known") <(printf '%s\n' "$idx") | tr '\n' ' ')"; fi
  refs="$(grep -rhoE 'pw-[a-z-]+\.sh' "$TOOL/skills/human" "$TOOL/agents" "$TOOL/skills/model" | sort -u)"
  allow="$(awk -F'\t' '!/^#/ && $1 {print $1}' "$TOOL/tests/expectations/unwired.ok" 2>/dev/null | sort -u)"
  hits="$(comm -23 <(printf '%s\n' "$refs") <(printf '%s\n' "$known" "$allow" | sort -u) )"
  [ -z "$hits" ] && pwtest_ok "T4 entry paths reference only registry/allowlisted scripts" \
    || pwtest_bad "T4 entry paths reference known scripts" "$hits"
  local unreferenced="$(comm -13 <(printf '%s\n' "$refs" "$allow" | sort -u) <(printf '%s\n' "$known"))"
  [ -z "$unreferenced" ] && pwtest_ok "T4 every automation script wired to an entry path" \
    || pwtest_bad "T4 every automation script wired" "unreferenced: $(printf '%s' "$unreferenced" | tr '\n' ' ') $(printf '%s\n' "$unreferenced" | while read -r z; do grep -l "$z" "$TOOL"/skills/human/*/SKILL.md >/dev/null 2>&1 && echo "(in commands)"; done)"

  # 2b) selector kinds need a selector: `pw-doc.sh lint --kind analysis|task` has no implicit
  #     "all". A preflight that omits --all/--file dies rc 2 before the phase can start (the
  #     /pw-breakdown block lost its --all during the named-flag migration and blocked every
  #     breakdown). Entry paths must spell the selector out.
  hits="$(grep -rnE 'pw-doc\.sh lint --kind (analysis|task)( |$)' "$TOOL/skills/human" "$TOOL/agents" "$TOOL/skills/model" \
    | grep -vE -- '--all|--file' || true)"
  [ -z "$hits" ] && pwtest_ok "T4 canary: pw-doc lint analysis/task calls name their selector" \
    || pwtest_bad "T4 canary: pw-doc lint --kind analysis|task needs --all or --file" "$(printf '%s' "$hits" | head -2 | cut -c1-140 | tr '\n' '|')"

  # 3) information boundary — only registry names; pw-env.sh remains the allowed human ref.
  #    A name that is NOT in the registry is worse: the reader is pointed at a file that does
  #    not exist. The allowed human refs are the ones the docs own.
  hits=""
  for n in $PWTEST_AUTOMATION; do
    for f in "$TOOL/../README.md" "$TOOL/../AGENTS.md" "$TOOL/../CLAUDE.md" "$TOOL/../ONBOARDING.md" "$TOOL/../docs/"*.md; do
      [ -f "$f" ] && grep -qF "$n" "$f" && hits="$hits $n@$(basename "$f")"
    done
  done
  for f in "$TOOL/../README.md" "$TOOL/../AGENTS.md" "$TOOL/../CLAUDE.md" "$TOOL/../ONBOARDING.md" "$TOOL/../docs/"*.md; do
    [ -f "$f" ] || continue
    for n in $(grep -ohE '[A-Za-z0-9._-]+\.sh' "$f" 2>/dev/null | sort -u); do
      case "$n" in
        pw.config.sh|pw.config.example.sh|pw-env.sh|bootstrap.sh|offboard.sh) continue ;;
      esac
      case " $PWTEST_AUTOMATION " in *" $n "*) continue ;; esac
      hits="$hits $n@$(basename "$f")"
    done
  done
  [ -z "$hits" ] && pwtest_ok "T4 user docs free of automation-script names" \
    || pwtest_bad "T4 user docs free of automation-script names" "$hits"

  # 3a) the user layer is self-contained (D3, mechanical): no machinery references outside the
  # docs/TOOLING.md hub. Root AGENTS.md is a pure user file (owner tightening 2026-09-25):
  # maintainers onboard via tooling/AGENTS.md directly, never a handoff pointer in the user layer.
  hits=""
  for f in "$TOOL/../README.md" "$TOOL/../AGENTS.md" "$TOOL/../CLAUDE.md" "$TOOL/../ONBOARDING.md" \
           "$TOOL/../docs/"*.md "$TOOL/../template/"*.md "$TOOL/../template/"*/*.md; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "TOOLING.md" ] && continue
    grep -q "tooling/" "$f" && hits="$hits $(basename "$f")"
  done
  [ -z "$hits" ] && pwtest_ok "T4 user layer free of machinery refs (TOOLING.md hub exempt)" \
    || pwtest_bad "T4 user layer free of machinery refs" "$hits"

  # 3c) templates carry command-only guidance (plan 30): a bare registry script name in any
  # template is a user-facing leak the D3 path-scan above cannot see (it only greps "tooling/"
  # paths; `pw-review.sh` in a template slipped through that way).
  hits=""
  for f in "$TOOL/../template/"*.md "$TOOL/../template/"*/*.md; do
    [ -f "$f" ] || continue
    for n in $PWTEST_AUTOMATION; do
      grep -qF "$n" "$f" && hits="$hits $n@${f#"$TOOL/../template/"}"
    done
  done
  [ -z "$hits" ] && pwtest_ok "T4 templates free of automation-script names (command-only)" \
    || pwtest_bad "T4 templates free of automation-script names" "$hits"

  # 3d) the TOOLING hub pins the tree, it does not deep-link it (plan 30): markdown links into
  # ../tooling/ from the one user-layer exemption are maintainer navigation that belongs in
  # tooling/AGENTS.md. Prose naming the tree stays allowed (that is the hub's whole job).
  hits="$(grep -nE '\]\(\.\.?/tooling/' "$TOOL/../docs/TOOLING.md" 2>/dev/null | head -2 | tr '\n' ' ')"
  [ -z "$hits" ] && pwtest_ok "T4 TOOLING.md carries no maintainer deep links" \
    || pwtest_bad "T4 TOOLING.md deep links" "found: $hits — the hub names the tree; tooling/AGENTS.md navigates it"

  # 3e) the command relay clauses pin the command-only final-reply contract (plan 30): raw script
  # diagnostics stay in the agent's working context; the user reply carries cause + /pw-* recovery.
  grep -qF 'final reply' "$TOOL/skills/human/pw-context/SKILL.md" \
    && grep -qF '/pw-*` action' "$TOOL/skills/human/pw-context/SKILL.md" \
    && grep -qF 'final reply' "$TOOL/skills/human/pw-review/SKILL.md" \
    && pwtest_ok "T4 canary: command relay clauses pin the command-only final reply" \
    || pwtest_bad "T4 command reply boundary" "pw-context.md/pw-review.md lost the final-reply relay contract"

  # 3f) the agent-mediated operation contract (plan 52): one bridge rule in the loaded skill,
  # one closed update operator in the status command, and the vocabulary pinned in the writer.
  grep -qF 'Agent-mediated operations' "$TOOL/skills/model/pw-guide-workflow/SKILL.md" \
    && grep -qF 'pw-status update --project' "$TOOL/skills/human/pw-status/SKILL.md" \
    && grep -qF 'PW_UPDATE_STATUSES="complete accepted review"' "$TOOL/scripts/entities/pw-status.sh" \
    && pwtest_ok "T4 canary: agent-mediated operation contract" \
    || pwtest_bad "T4 agent-mediated contract" "skill bridge rule, pw-status update forms, or the closed status vocabulary was removed"

  # 3b) internal plan numbers / issue-record labels never reach published prose — scope now covers
  # root *.md, template/, and tooling/docs (tooling/skill-internal is maintainer-facing, unshipped).
  hits=""
  for f in "$TOOL/../"*.md "$TOOL/../docs/"*.md "$TOOL/../template/"*.md "$TOOL/../template/"*/*.md \
           "$TOOL"/skills/human/*/SKILL.md "$TOOL"/agents/*.md "$TOOL"/skills/model/*/*.md "$TOOL"/skills/model/*/*/*.md \
           "$TOOL"/docs/*.md "$TOOL"/docs/scripts/*.md; do
    [ -f "$f" ] && grep -qE '\b[Pp]lans?[ .-]?[1-9][0-9]\b|\bKI-[0-9]\b' "$f" && hits="$hits $f"
  done
  [ -z "$hits" ] && pwtest_ok "T4 no internal plan references in published files" \
    || pwtest_bad "T4 no internal plan references" "$hits"

  # 4) doctrine canaries
  # audience split (users: bundle-root AGENTS.md; maintainers: tooling/AGENTS.md + CLAUDE.md) —
  # the doctrine must live in the maintainer entry point, and the user entry point must stay
  # clean of it (owner tightening 2026-09-25: no handoff pointer in the root file; maintainers
  # onboard via tooling/AGENTS.md directly).
  grep -qF 'single source of truth' "$TOOL/AGENTS.md" \
    && ! grep -q "tooling/" "$TOOL/../AGENTS.md" && grep -qF '@AGENTS.md' "$TOOL/CLAUDE.md" \
    && pwtest_ok "T4 canary: sources-only doctrine in tooling/AGENTS.md + clean user entry + tooling CLAUDE import" \
    || pwtest_bad "T4 canary: sources-only doctrine" "doctrine text missing from tooling/AGENTS.md, or a machinery ref crept into the user entry point, or tooling CLAUDE.md import died (C23: this exact rule dying cost a fixes round)"
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
  grep -qF 'HUMAN-TRIGGERED ONLY' "$TOOL/skills/human/pw-review/SKILL.md" \
    && pwtest_ok "T4 canary: signoff C4 doctrine line in pw-review.md" \
    || pwtest_bad "T4 canary: signoff C4 doctrine line" "pw-review.md lost the 'HUMAN-TRIGGERED ONLY' label on the signoff operator — the gate doctrine's only command-side guard"
  # (b) …and NO agent file may ever invoke it (anti-idiom: agent-side path is auto-signoff only)
  hits="$(grep -lE 'pw-review\.sh signoff|pw-review-edit\.sh' "$TOOL"/agents/*.md 2>/dev/null | tr '\n' ' ')"
  [ -z "$hits" ] && pwtest_ok "T4 canary: no agent file invokes signoff" \
    || pwtest_bad "T4 canary: no agent file invokes signoff" "C4 violation in: $hits — only a human triggers a gate decision (agent path: pw-review.sh auto-signoff)"
  grep -qF 'pw-review.sh init-docs --project <slug> --file <artifact-rel-path>' "$TOOL/skills/human/pw-review/SKILL.md" \
    && grep -qF '/pw-review init --project <project-slug> --file <artifact-rel-path>' "$TOOL/skills/human/pw-review/SKILL.md" \
    && ! grep -qF 'pw-review.sh init --project <slug> --file <artifact-rel-path>' "$TOOL/skills/human/pw-review/SKILL.md" \
    && pwtest_ok "T4 canary: selected document command maps to list initialization" \
    || pwtest_bad "T4 canary: selected document command mapping" "public init must accept artifact paths and call init-docs, not the legacy review/doc pair API"
  grep -qF "The reviewer must confirm its own execution identity." "$TOOL/skills/human/pw-review/SKILL.md" \
    && grep -qF 'never substitute the configured model pin' "$TOOL/agents/pw-reviewer.md" \
    && pwtest_ok "T4 canary: AI identity belongs to the reviewer, not the orchestrator" \
    || pwtest_bad "T4 canary: actual AI reviewer identity" "review handoff must distinguish actual reviewer runtime identity from requested routing and the spawning agent"
  # (c) capability-placement conventions doc exists, is linked from the maintainer entry,
  # and the pw-lib legacy core is fully dissolved (S2 endgame, plan 20)
  [ -f "$TOOL/docs/conventions.md" ] && grep -qF 'docs/conventions.md' "$TOOL/AGENTS.md" \
    && [ ! -e "$TOOL/pw-lib.sh" ] \
    && pwtest_ok "T4 canary: conventions.md exists + linked; pw-lib.sh dissolved" \
    || pwtest_bad "T4 canary: conventions doc + pw-lib dissolution" "tooling/docs/conventions.md missing, or its tooling/AGENTS.md link died, or pw-lib.sh survived the dissolution"
  # (d) the new entity scripts keep their group-doc section (usage reference completeness)
  grep -qF 'pw-review.sh' "$TOOL/docs/scripts/review-and-context-editing.md" \
    && grep -qF 'pw-context.sh' "$TOOL/docs/scripts/review-and-context-editing.md" \
    && pwtest_ok "T4 canary: review-and-context-editing group doc covers both scripts" \
    || pwtest_bad "T4 canary: group doc coverage" "docs/scripts/review-and-context-editing.md lost a script section — no doc-less capability ships"
  # (e) plan-19 harness mechanics documented — no speedup ships undocumented:
  grep -qF '## Inside the harness' "$TOOL/docs/testing.md" \
    && grep -qF '## Writing a mutation row' "$TOOL/docs/testing.md" \
    && grep -qF 'PWTEST_MUT_JOBS' "$TOOL/docs/testing.md" \
    && grep -qF 'PWTEST_MUT_TIMEOUT' "$TOOL/docs/testing.md" \
    && pwtest_ok "T4 canary: harness internals + env knobs + row-authoring documented" \
    || pwtest_bad "T4 canary: harness docs" "testing.md lost §Inside the harness / §Writing a mutation row or the PWTEST_MUT_* knob names"  # (f) pw-help forcing function (plan 18): the phase map == the commands tree, the
  # conventions checklist keeps the map-duty line, and pw-help.sh stays a leaf — no
  # script/agent/skill/template may invoke help (only its command file + tests + docs).
  local mapcmds treecmds
  mapcmds="$(sed -n 's/^HELP_PHASE_MAP="\(.*\)"$/\1/p' "$TOOL/scripts/entities/pw-help.sh")"
  mapcmds="$(printf '%s\n' "$mapcmds" | tr ';|' '\n\n' | tr ' ' '\n' | grep -E '^pw-[a-z0-9-]+$' | sort -u)"
  treecmds="$(cd "$TOOL/skills/human" && ls -d */ | sed 's#/##' | sort -u)"
  [ "$mapcmds" = "$treecmds" ] && pwtest_ok "T4 canary: pw-help phase map == the commands tree (forcing function)" \
    || pwtest_bad "T4 canary: pw-help phase map == commands tree" "$(comm -3 <(printf '%s\n' "$mapcmds") <(printf '%s\n' "$treecmds") | tr '\n' ' ') — add the command to HELP_PHASE_MAP in the same commit (conventions.md checklist)"
  grep -qF 'phase map' "$TOOL/docs/conventions.md" \
    && pwtest_ok "T4 canary: conventions checklist carries the pw-help phase-map duty" \
    || pwtest_bad "T4 canary: conventions checklist phase-map duty" "the durable map-duty line vanished from conventions.md"
  hits="$(grep -rl 'pw-help\.sh' "$TOOL/agents" "$TOOL/scripts/entities" "$TOOL/scripts/lib" "$TOOL/scripts/toolchain" "$TOOL/../template" 2>/dev/null | grep -v '/pw-help\.sh$' | tr '\n' ' ')"
  # skill files MAY teach invocation (guidance surfaces, like docs); agents/scripts/templates may
  # not consume help as a data source — that is the S5 rule the leaf protects.
  [ -z "$hits" ] && pwtest_ok "T4 canary: pw-help.sh is a leaf (no script/agent/template consumes it)" \
    || pwtest_bad "T4 canary: pw-help.sh leaf" "help consumed as a dependency in: $hits — doctrine: help renders for callers, scripts share libs (S5)"


  # (g) plan-22 routing-ladder canaries: the ONE ladder text lives in the skill reference and is
  # referenced (not re-described) by the entry paths…
  grep -qF 'AVAILABILITY GATE first — on EVERY path, including resume:' "$TOOL/skills/model/pw-guide-workflow/references/execution-and-routing.md" \
    && grep -qF 'Route resolution' "$TOOL/skills/model/pw-guide-workflow/references/execution-and-routing.md" \
    && grep -qF 'Headless supervision (never fire-and-forget):' "$TOOL/skills/model/pw-guide-workflow/references/execution-and-routing.md" \
    && grep -qF 'session-check' "$TOOL/skills/model/pw-guide-workflow/references/execution-and-routing.md" \
    && grep -qF 'session-check' "$TOOL/skills/model/pw-guide-workflow/references/review.md" \
    && pwtest_ok "T4 canary: one ladder + script-decided liveness in the skill reference" \
    || pwtest_bad "T4 canary: routing ladder text" "the ladder/availability-gate/session-check text died from execution-and-routing.md or review.md — commands must *reference* it, commands+agents+refs must not re-describe policy" ;\
  grep -qF 'ladder' "$TOOL/skills/human/pw-ship/SKILL.md" && grep -qF 'ladder' "$TOOL/skills/human/pw-review/SKILL.md" \
    && grep -qF 'model-resolve' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && pwtest_ok "T4 canary: entry paths reference the ladder (no per-command policy rewording)" \
    || pwtest_bad "T4 canary: entry-path ladder references" "pw-ship/pw-review lost the ladder reference, or pw-execute lost the availability gate"
  # request-review routing: the read-only message mode must stay documented in /pw-ship and must
  # stay positioned BEFORE the ship pre-flight (its tokens are a selector, not ship task IDs).
  grep -qF 'pw-ship.sh request-review' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && grep -qF 'returns BEFORE the pre-flight block' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && grep -qF -- '--prose <file>' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && pwtest_ok "T4 canary: pw-ship request-review routing text" \
    || pwtest_bad "T4 canary: pw-ship request-review routing" "the read-only request-review mode (selector mapping, pre-flight ordering, --prose flow) died from the command file"
  # sync opt-in conflict resolution (plan 48): the boolean flag, the default-abort contract, and
  # the conditionally loaded procedure must all stay wired; the procedure must keep the
  # deterministic finish/bind path rather than re-describing a raw edit-and-push loop.
  grep -qF -- '[--auto-resolve]' "$TOOL/skills/human/pw-sync/SKILL.md" \
    && grep -qF 'Conflict without the flag?' "$TOOL/skills/human/pw-sync/SKILL.md" \
    && grep -qF 'references/sync-conflict-resolution.md' "$TOOL/skills/human/pw-sync/SKILL.md" \
    && grep -qF 'sync-finish' "$TOOL/skills/model/pw-guide-workflow/references/sync-conflict-resolution.md" \
    && grep -qF 'sync-bind' "$TOOL/skills/model/pw-guide-workflow/references/sync-conflict-resolution.md" \
    && grep -qF 'Never resolve a path by choosing one side' "$TOOL/skills/model/pw-guide-workflow/references/sync-conflict-resolution.md" \
    && grep -qF 'Preserve both sides' "$TOOL/skills/human/pw-sync/SKILL.md" \
    && grep -qF -- '--allow-one-sided' "$TOOL/skills/model/pw-guide-workflow/references/sync-conflict-resolution.md" \
    && grep -qF -- '--owner-approved' "$TOOL/skills/model/pw-guide-workflow/references/sync-conflict-resolution.md" \
    && pwtest_ok "T4 canary: sync opt-in conflict resolution wiring" \
    || pwtest_bad "T4 canary: sync opt-in conflict resolution wiring" "the --auto-resolve flag, default-abort text, reference pointer, finish/bind procedure, or two-sided preservation rule died"
  # assisted preparation writes an optional feedback record; the doctor must say so, or the
  # user never learns the record exists.
  grep -qF 'Assisted preparation also creates an optional feedback record at `review/CONTEXT.review.md`.' "$TOOL/scripts/entities/pw-project-doctor.sh" \
    && pwtest_ok "T4 canary: assisted preparation feedback record is documented" \
    || pwtest_bad "T4 canary: assisted preparation feedback record" "pw-project-doctor.sh lost the note about the optional review/CONTEXT.review.md record"
  # generation-prompt wiring: the two-call prose flow must name the editable prompt files and the
  # observed-head comparison — losing either re-opens ungrounded prose generation. The procedure
  # lives in the request-review reference; the command must still point at it.
  grep -qF '**Load `references/review-request.md` from the `pw-guide-workflow` skill**' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && grep -qF 'references/review-request.md' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && grep -qF 'user/prompts/review-request-summary.md' "$TOOL/skills/model/pw-guide-workflow/references/review-request.md" \
    && grep -qF 'PW_REVIEW_REQUEST_NOTE_PROMPT_FILE' "$TOOL/skills/model/pw-guide-workflow/references/review-request.md" \
    && grep -qF 'Compare `observed heads`' "$TOOL/skills/model/pw-guide-workflow/references/review-request.md" \
    && pwtest_ok "T4 canary: pw-ship generation-prompt wiring text" \
    || pwtest_bad "T4 canary: pw-ship generation-prompt wiring" "the command lost its request-review reference, or the editable prompt files / observed-head comparison died from the request-review reference"
  # the review command must offer the whole --surface list: a narrowed list silently drops
  # surfaces the agent can select (the surface vocabulary is the review scope contract).
  grep -qF '[--surface <context|analysis|plan|task-plan|task-exec|ship|rfc|close>' "$TOOL/skills/human/pw-review/SKILL.md" \
    && pwtest_ok "T4 canary: pw-review offers the full --surface list" \
    || pwtest_bad "T4 canary: pw-review --surface list" "the --surface vocabulary in pw-review.md lost a surface; the list is the review scope contract"
  # named dispatch + entry-before-assessment doctrine (plan 46): the ship command selects modes by
  # operation word (never an ordinal argument slot), and every reviewer instruction surface keeps
  # the correlated pass entry strictly before assessment.
  grep -qF 'The first word selects the mode:' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && ! grep -qF '2nd argument' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && pwtest_ok "T4 canary: ship dispatch prose selects operation words" \
    || pwtest_bad "T4 canary: ship dispatch prose" "pw-ship.md lost the first-word dispatch contract (or an ordinal-slot phrase returned)"
  grep -qF 'FIRST records the entry with' "$TOOL/skills/human/pw-review/SKILL.md" \
    && grep -qF 'and FIRST record that' "$TOOL/agents/pw-reviewer.md" \
    && grep -qF 'comes before assessment' "$TOOL/skills/model/pw-guide-review-method/SKILL.md" \
    && pwtest_ok "T4 canary: reviewer entry precedes assessment in every instruction surface" \
    || pwtest_bad "T4 canary: entry-before-assessment routing" "a reviewer instruction surface lost the entry-first contract"
  # context review completion parity (plan 44): the shared preparation reference and the command
  # dispatcher must both carry the optional record + completion handoff, and init-all must not send
  # users to analysis as the first reviewable artifact.
  grep -qF 'Run the completion handoff exactly once after verification' "$TOOL/skills/model/pw-guide-workflow/references/context.md" \
    && grep -qF 'Completion review — only when configured' "$TOOL/skills/human/pw-context/SKILL.md" \
    && grep -qF 'Ensure the optional separate readiness record when a brief exists' "$TOOL/skills/model/pw-guide-workflow/references/context.md" \
    && pwtest_ok "T4 canary: context preparation carries the review handoff" \
    || pwtest_bad "T4 canary: context review handoff" "a preparation instruction surface lost the record/completion contract"
  grep -qF 'context readiness review is optional' "$TOOL/scripts/entities/pw-review.sh" \
    && ! grep -qF '/pw-analyze $slug produces the first reviewable analysis' "$TOOL/scripts/entities/pw-review.sh" \
    && pwtest_ok "T4 canary: init-all context guidance is accurate" \
    || pwtest_bad "T4 canary: init-all context guidance" "context init-all still claims analysis produces the first reviewable artifact"
  grep -qF 'context|analysis|plan|task-plan|task-exec|ship' "$TOOL/scripts/entities/pw-preflight.sh" \
    && pwtest_ok "T4 canary: review preflight accepts the context lane" \
    || pwtest_bad "T4 canary: review preflight context lane" "context lane missing from the review gate"
  # /user/ ignore coverage: representative frame, prompt, and scratch files must be ignored, the
  # legacy location stays ignored during migration, and no user-owned customization may be tracked.
  _giterr=""
  if [ -d "$TOOL/../.git" ]; then
    for _u in user/templates/review-request.md user/prompts/review-request-summary.md \
              user/prompts/review-request-note.md user/scratch.txt user-templates/legacy.md; do
      git -C "$TOOL/.." check-ignore -q "$_u" 2>/dev/null || _giterr="$_giterr $_u"
    done
    [ -z "$_giterr" ] && pwtest_ok "T4 canary: /user/ gitignore covers frame, prompts, and scratch files" \
      || pwtest_bad "T4 canary: /user/ gitignore coverage" "not ignored:$_giterr"
  else
    # a disposable copy carries no .git: ignore coverage cannot be checked here, and a
    # failed check would make every sweep child red for a reason no mutation caused.
    pwtest_ok "T4 canary: /user/ gitignore coverage skipped (no .git in this tree)"
  fi
  _tracked="$(git -C "$TOOL/.." ls-files 'user/**' 'user-templates/**' 2>/dev/null)"
  [ -z "$_tracked" ] && pwtest_ok "T4 canary: no user-owned customization is tracked" \
    || pwtest_bad "T4 canary: no tracked user customization" "tracked: $_tracked — untrack it with git rm --cached (the local file stays)"
  # …and the RETIRED repair-routing policy text never creeps back (resume-first default, the `!`
  # shorthand, the dropped global flag, the merged fourth Route value, the producer-resume clause).
  hits="$(grep -rlE 'Execute with!|PW_STRICT_MODELS|Route: resume|resume that producer|batched, resume-first|batched \+ resume-first' "$TOOL/skills/human" "$TOOL/agents" "$TOOL/skills/model" "$TOOL/docs" 2>/dev/null | tr '\n' ' ')"
  [ -z "$hits" ] && pwtest_ok "T4 canary: retired repair-routing text stays retired" \
    || pwtest_bad "T4 canary: retired repair-routing text" "reappeared in: $hits"

  # (h) explicit-line doctrine canaries: every config line is always present with an explicit
  # value — the dashboard template carries the AI Review line with its scaffold token, and
  # scaffold.sh still renders it. Losing either half re-creates the template↔render drift where
  # fresh projects silently start without an `AI Review:` line.
  grep -qE '^- \*\*AI Review:\*\* <AI_REVIEW_DEFAULT>' "$TOOL/../template/PROJECT.template.md" \
    && pwtest_ok "T4 canary: AI Review line is explicit in the dashboard template" \
    || pwtest_bad "T4 canary: AI Review line in template" "PROJECT.template.md lost its '- **AI Review:** <AI_REVIEW_DEFAULT>' line — absence must stay a defect, not the default"
  grep -qF '<AI_REVIEW_DEFAULT>' "$TOOL/scripts/toolchain/scaffold.sh" \
    && pwtest_ok "T4 canary: scaffold still renders <AI_REVIEW_DEFAULT>" \
    || pwtest_bad "T4 canary: scaffold AI-Review render" "scaffold.sh no longer seds <AI_REVIEW_DEFAULT> — the template token would ship unexpanded"
  # (i) the configuration domain left /pw-review for /pw-config — the retired recipe form must
  # never resurface in any published surface (pattern kept backtick-free: it runs unquoted).
  hits="$(grep -rlE 'pw-review [^ ]+ config (model|analysis|plan|task-plan|task-exec|ship|<phase>)' "$TOOL/skills/human" "$TOOL/agents" "$TOOL/skills/model" "$TOOL/docs" "$TOOL/../docs" "$TOOL/../README.md" "$TOOL/../AGENTS.md" 2>/dev/null | tr '\n' ' ')"
  [ -z "$hits" ] && pwtest_ok "T4 canary: retired /pw-review config recipes stay retired" \
    || pwtest_bad "T4 canary: retired config recipes" "reappeared in: $hits — configuration lives on /pw-config"

  # (j) plan-23 D-rules: the user known-issues page stays retired — no file, zero references
  # outside the harness, no maintainer-shape records in user docs, the D-rules doctrine lives in
  # conventions.md, and the maintainer backlog exists and is linked from tooling/README.md.
  if [ ! -e "$TOOL/../docs/KNOWN-ISSUES.md" ]; then pwtest_ok "T4 canary: user KNOWN-ISSUES page stays retired (D4)"
  else pwtest_bad "T4 canary: user KNOWN-ISSUES page retired" "docs/KNOWN-ISSUES.md exists again — D4: a known issue is a maintainer state (tooling/docs/known-issues.md), never a user genre"; fi
  hits="$(grep -rl 'KNOWN-ISSUES' "$TOOL/.." --include='*.md' --include='*.sh' 2>/dev/null | grep -v '/tests/' | tr '\n' ' ')"
  [ -z "$hits" ] && pwtest_ok "T4 canary: zero stale KNOWN-ISSUES references outside the harness" \
    || pwtest_bad "T4 stale KNOWN-ISSUES references" "$hits — repoint by D2: user symptom → docs/TROUBLESHOOTING.md, defect → tooling/docs/known-issues.md, settled → mechanism doc"
  hits="$(grep -rl 'Mitigation (built in)' "$TOOL/../docs/"*.md 2>/dev/null | tr '\n' ' ')"
  [ -z "$hits" ] && pwtest_ok "T4 canary: no maintainer-shape records in user docs (D1)" \
    || pwtest_bad "T4 user-doc record shape" "$hits — settled-gotcha records belong in tooling/docs/ (D2), user docs carry symptoms+actions only"
  grep -qF '## D-rules' "$TOOL/docs/conventions.md" \
    && [ -f "$TOOL/docs/known-issues.md" ] && grep -qF 'known-issues.md' "$TOOL/README.md" \
    && grep -qF 'TROUBLESHOOTING' "$TOOL/docs/known-issues.md" \
    && pwtest_ok "T4 canary: D-rules doctrine + maintainer backlog present and linked" \
    || pwtest_bad "T4 D-rules/backlog" "conventions.md lost its D-rules section, tooling/docs/known-issues.md is missing or lost its tooling/README.md link, or the backlog lost its TROUBLESHOOTING routing row"


  # (k) stacked-policy branches at the ship/sync decision points: the canonical command prose must
  # carry the stacked branch where the old wording was independent-only (selection, target, diff,
  # merged-parent settle-before-remove, no-comment cascade, fixer ordering) — a regression there
  # would re-describe policy the scripts no longer follow.
  grep -qF 'transitive stack descendants' "$TOOL/skills/model/pw-guide-workflow/references/mr-comments.md" \
    && grep -qF 'effective target' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && grep -qF 'never** fixed concurrently' "$TOOL/skills/model/pw-guide-workflow/references/mr-comments.md" \
    && grep -qF 'transitive stack descendants' "$TOOL/skills/human/pw-sync/SKILL.md" \
    && grep -qF 'settle the stack before removing' "$TOOL/skills/human/pw-sync/SKILL.md" \
    && grep -qF 'effective target' "$TOOL/skills/human/pw-sync/SKILL.md" \
    && grep -qF 'never concurrently' "$TOOL/skills/model/pw-guide-workflow/references/execution-and-routing.md" \
    && pwtest_ok "T4 canary: ship/sync commands carry the stacked-policy branches" \
    || pwtest_bad "T4 canary: ship/sync stacked-policy branches" "a stacked branch died from pw-ship.md/pw-sync.md/mr-comments.md or the routing ladder — the command prose fell back to independent-only instructions the scripts no longer match"

  # (l) the commands bind verification/landing through the deterministic operators: stack-verify is
  # the only verification writer the execution path names, promotion uses stack-retarget, and no
  # command asks the generic stack-record to certify a verified_head.
  grep -qF 'stack-verify --project <slug> --task <T0n>' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'stack-retarget' "$TOOL/skills/human/pw-sync/SKILL.md" \
    && ! grep -qE 'stack-record [^`]*verified_head=' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && pwtest_ok "T4 canary: commands bind verification via stack-verify and promote via stack-retarget" \
    || pwtest_bad "T4 canary: stack verification wiring" "pw-execute.md must call stack-verify (not stack-record verified_head=) and pw-sync.md must call stack-retarget"

  # (m) the cascade/history interop stays wired in prose: the command protocol names the
  # deterministic cascade + inherited-update writers (descendants update without fabricated
  # reviewer requests, as a distinct inherited round) and the maintainer doc lists the cascade.
  grep -qF 'references/mr-comments.md' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && grep -qF 'stack-cascade' "$TOOL/skills/model/pw-guide-workflow/references/mr-comments.md" \
    && grep -qF 'stack-inherited' "$TOOL/skills/model/pw-guide-workflow/references/mr-comments.md" \
    && grep -qF 'inherited-update round' "$TOOL/skills/model/pw-guide-workflow/references/mr-comments.md" \
    && grep -qF 'stack-cascade' "$TOOL/docs/scripts/ship-and-sync.md" \
    && pwtest_ok "T4 canary: stack cascade + inherited-update writers named in command and maintainer docs" \
    || pwtest_bad "T4 canary: stack cascade wiring" "pw-ship.md must point at references/mr-comments.md, which must name stack-cascade/stack-inherited (distinct inherited-update round), and ship-and-sync.md must list stack-cascade"

  # 5) shared plumbing used, not reinvented
  for f in $PWTEST_AUTOMATION; do
    grep -q 'pw-common\.sh' "$(pwtest_script "$f")" && pwtest_ok "T4: $f sources pw-common" || pwtest_bad "T4: $f sources pw-common" "P2 violation (readers re-implemented)"
  done

  # 6) L-rules layout canaries (tooling/docs/conventions.md): no file ships outside its kind-dir,
  # no caller references a layout path it must not know, and the registry mirrors the tree.
  # (a) dead-path: zero flat tooling/<entry>.sh refs anywhere (pw-lib dissolved — no exemption)
  hits="$(grep -rlE 'tooling/(pw-[a-z0-9-]+|scaffold|gen-[a-z-]+)\.sh' "$TOOL/.." --include='*.sh' --include='*.md' 2>/dev/null \
    | grep -v 'tests/static\.sh$' | tr '\n' ' ')"
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
  hits="$(grep -rl 'scripts/lib/' "$TOOL/skills/human" "$TOOL/agents" "$TOOL/skills/model" 2>/dev/null | tr '\n' ' ')"
  [ -z "$hits" ] && pwtest_ok "T4: no entry path references scripts/lib/ (L2)" \
    || pwtest_bad "T4: no entry path references scripts/lib/" "$hits"
  # (d) toolchain allowlist (L3): entry paths may name scripts/toolchain/ only per toolchain.ok
  local ok f2 pair hits2=""
  ok="$TOOL/tests/expectations/toolchain.ok"
  hits2="$(grep -rlE 'scripts/toolchain/[a-z-]+\.sh' "$TOOL/skills/human" "$TOOL/agents" "$TOOL/skills/model" 2>/dev/null | while read -r f2; do
      grep -ohE 'scripts/toolchain/[a-z-]+\.sh' "$f2" | sed "s|^|${f2#$TOOL/}\t|"
    done | sort -u)"
  known="$(grep -v '^#' "$ok" 2>/dev/null | sort -u)"
  [ -z "$(comm -23 <(printf '%s\n' "$hits2") <(printf '%s\n' "$known"))" ] \
    && pwtest_ok "T4: toolchain refs ⊆ allowlist (L3)" \
    || pwtest_bad "T4: toolchain refs ⊆ allowlist" "$(comm -23 <(printf '%s\n' "$hits2") <(printf '%s\n' "$known") | tr '\n' ' ') — L3: workflow entry paths may invoke toolchain scripts only per expectations/toolchain.ok"
  # (e) runtime hint strings must never name a script that doesn't exist (plan 20 fallout: the
  # merged pw-doc.sh carried dead `pw-doc-lint.sh` usage strings — users were told to run files
  # that are gone; L5 only scans tooling/-prefixed paths, so bare names in hints slipped).
  local bad="" tok xref
  for f2 in "$TOOL"/scripts/entities/*.sh "$TOOL"/scripts/toolchain/*.sh; do
    while IFS= read -r tok; do
      { [ -f "$TOOL/scripts/entities/$tok" ] || [ -f "$TOOL/scripts/lib/$tok" ] || [ -f "$TOOL/scripts/toolchain/$tok" ] || [ -f "$TOOL/../$tok" ]; } || bad="$bad $(basename "$f2")→$tok"
    done < <(grep -E 'usage:|die_fix|add_error' "$f2" | grep -oE '[a-z][a-z0-9.-]*\.sh' | sort -u)
  done
  [ -z "$bad" ] && pwtest_ok "T4: usage/fix strings name only live scripts (L5b)" \
    || pwtest_bad "T4: usage/fix strings name only live scripts" "dead script names in runtime hints:$bad — L5b: point hints at the entity script + operator"
  # (f) operator cross-attribution: `pw-<entity>.sh <tok>` where <tok> is an operator of a
  # DIFFERENT entity is a stale pointer (plan 20 fallout: the skill kept saying
  # `pw-context.sh adopted` after adopted moved to pw-status). Tokens that are no entity's
  # operator are prose and exempt; per-file op sets are deliberately over-inclusive.
  xref="$(python3 - "$TOOL" <<'PY'
import re, sys, glob, os
tool = sys.argv[1]; root = os.path.dirname(tool)
ents = {}
for f in glob.glob(tool + "/scripts/entities/pw-*.sh"):
    ents[os.path.basename(f)] = set(re.findall(r'^ {2,4}([a-z][a-z0-9-]*)\)', open(f).read(), re.M))
globops = set().union(*ents.values())
hits = set()
for r in [tool+"/skills/human", tool+"/agents", tool+"/skills/model", tool+"/docs", root+"/docs", root+"/template"]:
    for dp, _, fs in os.walk(r):
        for fn in fs:
            if not fn.endswith(".md"): continue
            p = os.path.join(dp, fn)
            for m in re.finditer(r'(pw-[a-z-]+\.sh) ([a-z][a-z0-9-]*)', open(p, errors="ignore").read()):
                s, tok = m.group(1), m.group(2)
                if s in ents and tok in globops and tok not in ents[s]:
                    hits.add(f"{os.path.relpath(p, root)}: {s} {tok}")
print(" ".join(sorted(hits)))
PY
)"
   [ -z "$xref" ] && pwtest_ok "T4: entity refs use that entity's own operators (L5c)" \
     || pwtest_bad "T4: entity refs vs operator sets" "misattributed operators: $xref — L5c: the entity owning the artifact owns the operator"

  # (g2) plan 29: human-entry / shared-skill split, exclusive provider output, no primary agent.
  local hcount mcount missing_entry bad_entry rendered
  hcount="$(ls -d "$TOOL/skills/human"/*/ 2>/dev/null | wc -l | tr -d ' ')"
  mcount="$(ls -d "$TOOL/skills/model"/*/ 2>/dev/null | wc -l | tr -d ' ')"
  [ "$hcount" = 19 ] && [ "$mcount" = 4 ] \
    && pwtest_ok "T4 canary: 19 human entries and 4 shared skills (plan 29)" \
    || pwtest_bad "T4 canary: skill inventory" "expected 19 human + 4 shared; got $hcount + $mcount"
  missing_entry="$(grep -L '`pw-orchestration`' "$TOOL"/skills/human/*/SKILL.md 2>/dev/null | tr '\n' ' ')"
  [ -z "$missing_entry" ] \
    && pwtest_ok "T4 canary: every human entry loads the shared orchestration rules" \
    || pwtest_bad "T4 canary: orchestration wiring" "entry files without the orchestration load: $missing_entry"
  [ -f "$TOOL/skills/model/pw-orchestration/references/common.md" ] \
    && [ -f "$TOOL/skills/model/pw-orchestration/references/execution.md" ] \
    && grep -qF 'no custom primary agent' "$TOOL/skills/model/pw-orchestration/SKILL.md" \
    && ! ls "$TOOL/agents/pw-orchestrator.md" >/dev/null 2>&1 \
    && [ "$(ls "$TOOL"/agents/pw-*.md | wc -l | tr -d ' ')" = 6 ] \
    && [ -f "$TOOL/agents/pw-ship-comment-analyst.md" ] \
    && pwtest_ok "T4 canary: normal-session orchestration with six workers and no primary agent" \
    || pwtest_bad "T4 canary: orchestration inventory" "orchestration references/declaration missing, or the agent set is not exactly six workers"
  # 9a) /pw-ship comments analysis prerequisite: ONE read-only analyst gates every MR fixer;
  # groups inside an MR stay sequential, and independent MRs share the max-parallel ceiling.
  grep -qF 'Comment analysis prerequisite' "$TOOL/skills/model/pw-guide-workflow/references/mr-comments.md" \
    && grep -qF 'No source edit begins until its artifact is complete and' "$TOOL/skills/model/pw-guide-workflow/references/mr-comments.md" \
    && grep -qF 'groups never run as parallel writers' "$TOOL/skills/model/pw-guide-workflow/references/mr-comments.md" \
    && grep -qF 'the single analysis artifact is complete and validated.' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && grep -qF 'Read-only; never fixes' "$TOOL/agents/pw-ship-comment-analyst.md" \
    && grep -qF 'Six worker sub-agents ship' "$TOOL/skills/model/pw-guide-workflow/references/execution-and-routing.md" \
    && grep -qF '**Load `references/mr-comments.md` from the `pw-guide-workflow` skill**' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && grep -qF 'Concurrency is required, not optional.' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && grep -qF '**do not process them one after another**' "$TOOL/skills/model/pw-guide-workflow/references/mr-comments.md" \
    && pwtest_ok "T4 canary: comment analysis prerequisite gates every MR fixer" \
    || pwtest_bad "T4 canary: comment analysis prerequisite" "analyst barrier, sequential groups, max-parallel wording, or the six-worker inventory is missing"
  # 9b) the ship-comment-analyst role must be registered on EVERY authoritative role surface —
  # one missed list silently drops the row from get/set/show/ensure or the scaffolded dashboard.
  rmiss=""
  for rf in "$TOOL/scripts/lib/pw-common.sh" "$TOOL/scripts/entities/pw-config.sh" \
            "$TOOL/scripts/toolchain/scaffold.sh" "$TOOL/scripts/entities/pw-status.sh" \
            "$TOOL/skills/human/pw-config/SKILL.md" "$TOOL/../template/PROJECT.template.md"; do
    grep -qF 'ship-comment-analyst' "$rf" || rmiss="$rmiss ${rf#"$TOOL"/../}"
  done
  [ -z "$rmiss" ] && pwtest_ok "T4 canary: ship-comment-analyst registered on every role surface" \
    || pwtest_bad "T4 canary: ship-comment-analyst role surfaces" "missing:$rmiss"
  # 9c) cross-skill reference pointers must name their owning skill. Provider installs ship an
  # entry as SKILL.md only (no references/ beside it), so a bare `references/x.md` silently skips
  # the procedure — the plan-07 follow-up where Cursor fixed comments sequentially.
  unqual="$(python3 - "$TOOL" <<'PYP'
import re,sys,pathlib
tool=pathlib.Path(sys.argv[1]); bad=[]
pat=re.compile(r'(?<![-/])references/([a-z0-9-]+\.md)')
files=list((tool/'skills'/'human').glob('*/SKILL.md'))+list((tool/'agents').glob('pw-*.md')) \
      +list((tool/'skills'/'model').glob('*/SKILL.md'))+list((tool/'skills'/'model').glob('*/references/*.md'))
for f in files:
    lines=f.read_text().splitlines()
    in_refs=f.parent.name=='references'
    local_dir=f.parent if in_refs else f.parent/'references'
    for i,l in enumerate(lines):
        if re.search(r'tooling/skills/model/[a-z-]+/references/', l):
            continue
        for m in pat.finditer(l):
            if (local_dir/m.group(1)).exists():
                continue
            window=' '.join(lines[max(0,i-1):i+2])
            if re.search(r'pw-guide-[a-z-]+|pw-orchestration', window):
                continue
            bad.append(f"{f.name}:{i+1}:{m.group(1)}")
print(' '.join(bad))
PYP
)"
  [ -z "$unqual" ] && pwtest_ok "T4 canary: cross-skill references name their owning skill" \
    || pwtest_bad "T4 canary: cross-skill reference owner" "bare references/ pointer(s) unresolvable after install: $unqual"
  # 9d) relative Markdown links in agent-facing sources must resolve from THEIR OWN file — a
  # wrong-depth link (or a path that only existed pre-install) sends the agent to nothing.
  deadlinks="$(python3 - "$TOOL" <<'PYD'
import re,sys,pathlib
tool=pathlib.Path(sys.argv[1]); bad=[]
pat=re.compile(r'\[[^\]]*\]\(([^)\s]+)\)')
roots=[tool/'skills',tool/'agents',tool/'docs']
for root in roots:
    for f in root.rglob('*.md'):
        for i,l in enumerate(f.read_text().splitlines(),1):
            for m in pat.finditer(l):
                t=m.group(1)
                if t.startswith(('http://','https://','mailto:','#','{{','$')): continue
                if '<' in t or t.startswith('./T0'): continue
                q=t.split('#')[0]
                if q and not (f.parent/q).exists():
                    bad.append(f"{f.relative_to(tool)}:{i}")
print(' '.join(bad))
PYD
)"
  [ -z "$deadlinks" ] && pwtest_ok "T4 canary: relative doc links resolve from their own file" \
    || pwtest_bad "T4 canary: relative doc links" "unresolvable link(s): $deadlinks"
  rendered="$ROOT/plan29-entries"
  "$TOOL/scripts/toolchain/gen-commands.sh" --outdir "$rendered" claude cursor codex kilo opencode >/dev/null 2>&1
  bad_entry=""
  for _pf in claude cursor; do
    [ "$(ls -d "$rendered/$_pf"/*/ 2>/dev/null | wc -l | tr -d ' ')" = 19 ] || bad_entry="$bad_entry $_pf:skill-count"
    grep -qF 'disable-model-invocation: true' "$rendered/$_pf/pw-execute/SKILL.md" 2>/dev/null || bad_entry="$bad_entry $_pf:explicit-only"
    ls "$rendered/$_pf"/*.md >/dev/null 2>&1 && bad_entry="$bad_entry $_pf:command-files"
  done
  [ "$(ls -d "$rendered/codex"/*/ 2>/dev/null | wc -l | tr -d ' ')" = 19 ] || bad_entry="$bad_entry codex:skill-count"
  grep -qF 'allow_implicit_invocation: false' "$rendered/codex/pw-execute/agents/openai.yaml" 2>/dev/null || bad_entry="$bad_entry codex:policy"
  grep -qF '<arguments>' "$rendered/codex/pw-execute/SKILL.md" 2>/dev/null || bad_entry="$bad_entry codex:args-token"
  grep -qF '$ARGUMENTS' "$rendered/codex/pw-execute/SKILL.md" 2>/dev/null && bad_entry="$bad_entry codex:claude-token"
  for _pf in kilo opencode; do
    [ "$(ls "$rendered/$_pf"/*.md 2>/dev/null | wc -l | tr -d ' ')" = 19 ] || bad_entry="$bad_entry $_pf:command-count"
    ls -d "$rendered/$_pf"/pw-*/ >/dev/null 2>&1 && bad_entry="$bad_entry $_pf:entry-skills"
  done
  [ -z "$bad_entry" ] \
    && pwtest_ok "T4 canary: exclusive provider output (skills-only claude/cursor/codex, commands-only kilo/opencode)" \
    || pwtest_bad "T4 canary: exclusive provider output" "unexpected artifacts:$bad_entry"

  # (g3) plan 59: one batch coordination entry over existing commands — a closed allowlist in
  # the command file, explicit authorization, stop-first partial reporting, and NO second
  # mutation engine (a pw-batch.sh entry point would turn coordination into a catch-all core).
  b_entry="$TOOL/skills/human/pw-batch/SKILL.md"
  b_ref="$TOOL/skills/model/pw-guide-workflow/references/batch.md"
  b_miss=""
  [ -f "$b_entry" ] || b_miss="$b_miss entry"
  [ -f "$b_ref" ] || b_miss="$b_miss reference"
  [ -f "$TOOL/scripts/entities/pw-batch.sh" ] && b_miss="$b_miss unexpected-script"
  grep -qE '^scope: mixed$' "$b_entry" 2>/dev/null || b_miss="$b_miss scope"
  grep -qE '^scope-forms: ".*=global' "$b_entry" 2>/dev/null && grep -qE '=project' "$b_entry" 2>/dev/null || b_miss="$b_miss scope-forms"
  grep -qF 'references/batch.md' "$b_entry" 2>/dev/null || b_miss="$b_miss reference-pointer"
  grep -qF '<!-- batch-ops:begin -->' "$b_entry" 2>/dev/null || b_miss="$b_miss allowlist-begin"
  grep -qF '<!-- batch-ops:end -->' "$b_entry" 2>/dev/null || b_miss="$b_miss allowlist-end"
  for _bneed in 'Never infer approval' 'On failure, refusal, or uncertainty, stop.' 'Preview writes nothing' 'No implicit repair' 'Refused forms include'; do
    grep -qF "$_bneed" "$b_entry" 2>/dev/null || b_miss="$b_miss missing:$_bneed"
  done
  for _bowner in '/pw-context' '/pw-review' '/pw-config' '/pw-status' '/pw-help' '/pw-doctor' '/pw-ship stack'; do
    grep -qF "$_bowner" "$b_entry" 2>/dev/null || b_miss="$b_miss owner:$_bowner"
  done
  b_rows="$(sed -n 's/^| `\(\/pw-[a-z-]*\).*/\1/p' "$b_entry" 2>/dev/null | sort -u)"
  [ -n "$b_rows" ] || b_miss="$b_miss allowlist-rows"
  for _bc in $b_rows; do
    [ -d "$TOOL/skills/human/${_bc#/}" ] || b_miss="$b_miss unknown:$_bc"
  done
  [ -z "$b_miss" ] \
    && pwtest_ok "T4 canary: pw-batch closed allowlist, authorization, stop-first, no new engine" \
    || pwtest_bad "T4 canary: pw-batch contract" "missing or drifted:$b_miss — keep the allowlist markers, contract anchors, and helper-free coordination intact"

  # (h) codex provider doctrine (plan 28): codex is the FIRST built-in with no native command
  # surface (custom prompts removed upstream in codex-cli 0.117.0) — its /pw-* commands are
  # generated SKILL DIRS in the shared skills root. The layout hook, the derived D13 skip
  # policy, the config.toml hands-off rule, and offboard's built-in list are one contract.
  grep -qF 'pw_provider_entry_format' "$TOOL/scripts/toolchain/gen-commands.sh" \
    && grep -qF 'codex_entry_format' "$TOOL/scripts/lib/pw-common.sh" \
    && grep -qF 'pw_skill_skips_for' "$TOOL/scripts/lib/pw-common.sh" \
    && grep -qF 'NEVER write ~/.codex/config.toml' "$TOOL/scripts/lib/pw-common.sh" \
    && grep -qF 'KNOWN_PROVIDERS=(claude kilo opencode cursor codex)' "$TOOL/../offboard.sh" \
    && pwtest_ok "T4 canary: codex skill-layout + D13 skips + config.toml hands-off + offboard list" \
    || pwtest_bad "T4 canary: codex provider doctrine" "a plan-28 anchor died: command_style hook (gen-commands.sh), codex hooks/skips/config.toml comment (pw-common.sh), or codex in offboard.sh KNOWN_PROVIDERS"

  # (i) named-argument contract canary (plan 46): the migrated user + agent surfaces must not
  # carry pre-migration invocation shapes. Bounded regexes over real invocation contexts only;
  # a controlled fixture proves the scanner still catches every banned class (no vacuous guard).
  local na_files na_cand na_hits na_fx na_fx_hits na_fx_ids
  na_files="$(cd "$TOOL/.." && printf '%s\n' \
    README.md AGENTS.md CLAUDE.md ONBOARDING.md \
    docs/*.md template/*.md template/*/*.md \
    tooling/README.md tooling/AGENTS.md tooling/CLAUDE.md \
    tooling/skills/human/*/SKILL.md tooling/skills/model/*/SKILL.md tooling/skills/model/*/*/*.md tooling/agents/*.md \
    tooling/docs/*.md tooling/docs/scripts/*.md \
    tooling/skill-internal/*/*.md tooling/skill-internal/*/*/*.md 2>/dev/null | sort -u \
    | while read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)"
  na_cand="$(cd "$TOOL/.." && grep -nH '/pw-' $na_files 2>/dev/null | grep -vE '^[^:]*:[0-9]+:#' || true)"
  na_hits="$(printf '%s\n' "$na_cand" | _pwtest_namedarg_scan)"
  [ -z "$na_hits" ] && pwtest_ok "T4 canary: named-argument contract holds on live surfaces (plan 46)" \
    || pwtest_bad "T4 canary: named-argument contract" "$(printf '%s' "$na_hits" | head -3 | tr '\n' ' ')"
  na_fx="$ROOT/namedarg-fixture.txt"
  printf '%s\n' \
    'fx:1:/pw-new delivery-note' \
    'fx:2:/pw-review delivery-note signoff analysis/review/x.review.md approved' \
    'fx:3:/pw-review --project proj item task/review/PLAN.review.md' \
    'fx:4:pw-config.sh project show myproj' \
    'fx:5:/pw-review item task/review/PLAN.review.md' \
    'fx:6:/pw-help project <slug>' \
    'fx:7:Multiple task IDs use spaces.' \
    'fx:8:Task IDs are `T01`; task IDs use spaces.' \
    'fx:9:<task-id>…' \
    'fx:10:/pw-new --project delivery-note' \
    'fx:11:/pw-review item --project proj --file task/review/PLAN.review.md --section Verification --text Fix' \
    'fx:12:/pw-config set --project proj --key max-parallel --value 2' \
    'fx:13:run /pw-new to scaffold a project' \
    'fx:14:/pw-ship comments --project proj' \
    'fx:15:/pw-help find --term review' \
    'fx:16:/pw-review --project <slug> [--phase plan | --task T01]' \
    'fx:17:$PW_HOME/tooling/scripts/entities/pw-status.sh log   <slug> <actor> <msg...>' \
    'fx:18:$PW_HOME/tooling/scripts/entities/pw-context.sh scan --repo repo-x --area src' \
    'fx:19:pw-ship.sh stack adopt --project <slug>' \
    'fx:20:pw-config.sh global show' > "$na_fx"
  na_fx_hits="$(cat "$na_fx" | _pwtest_namedarg_scan)"
  na_fx_ids="$(printf '%s\n' "$na_fx_hits" | grep -oE '^fx:[0-9]+' | tr '\n' ' ')"
  [ "$na_fx_ids" = "fx:1 fx:2 fx:3 fx:4 fx:5 fx:6 fx:7 fx:8 fx:9 fx:17 " ] \
    && pwtest_ok "T4 canary: named-argument scanner catches every banned class on the fixture" \
    || pwtest_bad "T4 canary: named-argument scanner fixture" "expected fx:1..fx:9 + fx:17 only; got: '${na_fx_ids:-none}' (a scanner class went vacuous or a valid form false-positives)"

  # (n) opt-in review-thread resolution (plan 49): `/pw-ship … comments` leaves handled threads OPEN
  # by default and closes them only under `--resolve`; the RFC comment flow stays externally
  # read-only and refuses a resolve flag. Losing either half re-opens silent auto-resolution.
  grep -qF '`--resolve` is a comment-mode-only switch' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && grep -qF 'leaves every thread open for your review' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && ! grep -qF 'also explicitly resolve it:' "$TOOL/skills/human/pw-ship/SKILL.md" \
    && ! grep -qE '^args:.*--resolve' "$TOOL/skills/human/pw-rfc/SKILL.md" \
    && grep -qF 'RFC comments are externally read-only' "$TOOL/scripts/entities/pw-rfc.sh" \
    && pwtest_ok "T4 canary: opt-in thread resolution + read-only RFC comments" \
    || pwtest_bad "T4 canary: opt-in thread resolution" "pw-ship.md lost the --resolve-opt-in contract (or an unconditional resolve instruction returned), or the RFC comment flow started advertising/accepting resolution"

  # (q) the bundle README is optional navigation, not an unconditional prompt payload.
  ! grep -qF 'Read `agentic-project-workflow/README.md` first' "$TOOL/../tooling/skills/model/pw-guide-workflow/SKILL.md" \
    && grep -qF 'Read the bundle README only' "$TOOL/../tooling/skills/model/pw-guide-workflow/SKILL.md" \
    && grep -qF 'when you need its user-facing overview or onboarding path' "$TOOL/../tooling/skills/model/pw-guide-workflow/SKILL.md" \
    && pwtest_ok "T4 canary: user README is conditional, not loaded on every workflow invocation" \
    || pwtest_bad "T4 canary: conditional README loading" "the skill must not require a blanket README read; keep the conditional overview/onboarding pointer"

  # (r) execute routes through the existing ladder/provider contract; detailed routing and CLI
  # gotchas stay in those canonical references instead of being duplicated in the command.
  grep -qF 'references/execution-and-routing.md' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'tooling/docs/providers.md' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'only' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'resolved cross-provider/headless route' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'Same-provider routes do not load the provider guide.' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'only when the' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'task declares either field' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'model-resolve' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'PW_HEADLESS_STALL' "$TOOL/skills/model/pw-guide-workflow/references/execution-and-routing.md" \
    && grep -qF '18 KB trailing argument' "$TOOL/docs/providers.md" \
    && grep -qF '`--auto` is **required** headless' "$TOOL/docs/providers.md" \
    && pwtest_ok "T4 canary: execute delegates routing and provider mechanics to canonical references" \
    || pwtest_bad "T4 canary: execute routing references" "the command must retain both references and model gate; canonical references must retain headless supervision and provider-specific prompt gotchas"

  # (t) provider catalog prose is conditional: only a cross-provider/headless route reads it.
  grep -qF 'only' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'resolved cross-provider/headless route' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'Same-provider routes do not load the provider guide.' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'only when the' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && grep -qF 'task declares either field' "$TOOL/skills/human/pw-execute/SKILL.md" \
    && pwtest_ok "T4 canary: provider guide is conditional on the selected route" \
    || pwtest_bad "T4 canary: provider guide loading" "pw-execute must not require provider mechanics for same-provider execution"

  # (s) the orchestrator uses the shared ladder rather than maintaining another copy of it.
  grep -qF 'The shared skill ladder owns' "$TOOL/skills/model/pw-orchestration/references/execution.md" \
    && grep -qF 'commands reference it, never re-describe it' "$TOOL/skills/model/pw-guide-workflow/references/execution-and-routing.md" \
    && pwtest_ok "T4 canary: orchestration delegates route resolution to the shared ladder" \
    || pwtest_bad "T4 canary: orchestration ladder reference" "pw-orchestration must point to the shared ladder, which remains the canonical routing contract"

  # (u) the mutation sweep sizes each row's watchdog to the work that row does, and
  #     re-measures a row that hit the watchdog: a kill is not a verdict.
  grep -qF '_pwtest_row_timeout' "$TOOL/tests/mutate.sh" \
    && grep -qF '_pwtest_mut_retry' "$TOOL/tests/mutate.sh" \
    && grep -qF '_pwtest_record_case_duration' "$TOOL/tests/pw_test_lib.sh" \
    && pwtest_ok "T4 canary: sweep watchdog follows the measured case cost and re-measures a killed row" \
    || pwtest_bad "T4 canary: sweep watchdog" "the sweep must derive a per-row watchdog from the measured case durations and re-run a row that hit the watchdog"

}
