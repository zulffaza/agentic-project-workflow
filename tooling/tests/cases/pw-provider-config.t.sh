# shellcheck shell=bash
# cases/pw-provider-config.t.sh — schema-2 provider-by-role cells, execution suggestions/routes,
# scope-aware batch suggestions, and explicit migration.

PC="$ROOT/provider-config"
rm -rf "$PC"; mkdir -p "$PC/projects" "$PC/repos" "$PC/proposals"
export PWTEST_KILO_CATALOG_EXTRA="command_code/model"
CFG="$PC/pw.config.sh"
printf '%s\n' \
  '# schema-2 test config' \
  'PW_PROVIDERS=(kilo cursor)' > "$CFG"
pc() { PW_PROJECTS_DIR="$PC/projects" PW_PROJECTS="$PC/projects" PW_REPOS="$PC/repos" \
       PW_CONFIG_FILE="$CFG" PW_PROPOSAL_DIR="$PC/proposals" "$(pwtest_script pw-config.sh)" "$@"; }
pc_scaffold() { PW_PROJECTS="$PC/projects" PW_REPOS="$PC/repos" PW_CONFIG_FILE="$CFG" \
       "$(pwtest_script scaffold.sh)" --project "$1"; }
pc_re() { printf '%s\n' "$2" | grep -qE -- "$1" && pwtest_ok "$3" || pwtest_bad "$3" "no /$1/ in [$2]"; }
pc_mk_task() { # <project> <task> [<execute-with>]
  local f="$PC/projects/$1/task/$2.md"
  cp "$PWTEST_TEMPLATE_DIR/task/_TEMPLATE-task.md" "$f"
  sed -i.bak -e "s/<T0n>/$2/g" "$f" && rm -f "$f.bak"
  if [ -n "${3:-}" ]; then
    sed -i.bak -e "s|^- \*\*Execute with:\*\* .*|- **Execute with:** $3|" "$f" && rm -f "$f.bak"
  fi
}

# --- global initialization cells ----------------------------------------------------------
pwtest_rc 0 "global role-model write" pc global set --key role-model --provider kilo --role analyst --model command_code/model --variant high
pc_eq="$(pc global get --key role-model --provider kilo --role analyst 2>/dev/null)"
pwtest_eq "global role-model read keeps provider:model" "kilo:command_code/model" "$pc_eq"
grep -q '^PW_PROJECT_ROLE_KILO_ANALYST_MODEL="command_code/model"$' "$CFG" \
  && pwtest_ok "global role cell lands in the managed block" \
  || pwtest_bad "global role cell lands in the managed block" "missing managed assignment"
grep -q '^PW_PROJECT_ROLE_KILO_ANALYST_VARIANT="high"$' "$CFG" \
  && pwtest_ok "global role tuning lands beside the model" \
  || pwtest_bad "global role tuning lands beside the model" "missing variant assignment"
bash -n "$CFG" && pwtest_ok "managed config stays valid shell" || pwtest_bad "managed config stays valid shell" "bash -n failed"

if pc global set --key role-model --provider opencode --role analyst --model x >/dev/null 2>&1; then
  pwtest_bad "disabled provider refused" "opencode is not in PW_PROVIDERS"
else pwtest_ok "disabled provider refused"; fi
if pc global set --key role-model --provider kilo --role analyst --model command_code/model --reasoning max >/dev/null 2>&1; then
  pwtest_bad "unverified global tuning refused" "kilo reasoning was accepted"
else pwtest_ok "unverified global tuning refused"; fi
pwtest_rc 0 "global role-model unset" pc global unset --key role-model --provider kilo --role analyst
pc_re 'unset' "$(pc global get --key role-model --provider kilo --role analyst 2>/dev/null)" "global role-model unset reads back empty"

pwtest_rc 0 "global execution suggestion write" pc global set --key execution-suggestion --current-provider kilo --execution-provider kilo --model command_code/model --subagent pw-executor
pc_re 'kilo kilo:command_code/model' "$(pc global get --key execution-suggestion 2>/dev/null)" "global suggestion reads back"
if pc global set --key execution-suggestion --current-provider kilo --execution-provider cursor --model no-such-model >/dev/null 2>&1; then
  pwtest_bad "global suggestion rejects an unavailable model" "no-such-model accepted"
else pwtest_ok "global suggestion rejects an unavailable model"; fi
pwtest_rc 0 "global execution suggestion unset" pc global unset --key execution-suggestion --current-provider kilo

# Global scope reuses the same batch engine: preview, override, explicit apply.
pwtest_rc 0 "global suggestion preview" pc suggest --scope global --set 'role-model:kilo:reviewer=command_code/model'
pc_eq="$(cat "$PWTEST_OUT")"
pc_re 'role-model:kilo:reviewer' "$pc_eq" "global preview lists the overridden cell"
pc_re 'explicit suggestion override' "$pc_eq" "global preview records the override"
GID="$(printf '%s\n' "$pc_eq" | sed -n 's/.*--apply \([^ ]*\).*/\1/p' | head -1)"
pwtest_rc 0 "apply the global batch" pc suggest --apply "$GID"
pc_re 'kilo:command_code/model' "$(pc global get --key role-model --provider kilo --role reviewer 2>/dev/null)" "global apply writes the cell"

# --- creation snapshot and readable tables ------------------------------------------------
pc global set --key role-model --provider kilo --role researcher --model command_code/model --variant high >/dev/null
pc global set --key role-model --provider cursor --role researcher --model cursor-test-high >/dev/null
pc global set --key execution-suggestion --current-provider kilo --execution-provider kilo --model command_code/model >/dev/null
pwtest_rc 0 "scaffold a schema-2 project" pc_scaffold demo
R="$PC/projects/demo/README.md"
grep -q '^- \*\*Configuration schema:\*\* 2$' "$R" \
  && pwtest_ok "new project carries the schema marker" \
  || pwtest_bad "new project carries the schema marker" "marker missing"
pc_re '^\| kilo \| researcher \| command_code/model \| high \|' "$(cat "$R")" "role table snapshots the kilo cell with tuning"
pc_re '^\| cursor \| researcher \| cursor-test-high \|' "$(cat "$R")" "role table snapshots every enabled provider column"
pc_re '^\| kilo \| analyst \| — \|' "$(cat "$R")" "unset cells stay visibly empty"
pc_re '^\| kilo \| kilo \| command_code/model \|' "$(cat "$R")" "execution suggestion snapshots the global row"
pc_re 'researcher=multiple' "$(grep '^- \*\*AI Models:\*\*' "$R")" "derived line marks a role populated by several providers"

# Snapshot is one-way: a later global change never rewrites the project.
pc global set --key role-model --provider kilo --role researcher --model command_code/other >/dev/null 2>&1 || true
pc_re '^\| kilo \| researcher \| command_code/model \| high \|' "$(cat "$R")" "existing project keeps the captured cell"

# --- project role cells -------------------------------------------------------------------
pwtest_rc 0 "project role-model write" pc set --project demo --key role-model --provider kilo --role analyst --model command_code/model
pc_re 'kilo analyst command_code/model' "$(pc get --project demo --key role-model 2>/dev/null)" "project role read lists the new cell"
pc_re 'kilo researcher command_code/model' "$(pc get --project demo --key role-model 2>/dev/null)" "composite key leaves the researcher row intact"
pc_re '^\- \*\*AI Models:\*\*' "$(grep '^- \*\*AI Models:\*\*' "$R")" "derived compatibility line survives project writes"
pwtest_rc 0 "spawn-args uses the project cell" pc spawn-args --project demo --role researcher --provider kilo
pc_re '^provider: kilo$' "$(cat "$PWTEST_OUT")" "spawn-args selects the provider column"
pc_re '^model: command_code/model$' "$(cat "$PWTEST_OUT")" "spawn-args reads the model from the table"
pc_re '^variant: high$' "$(cat "$PWTEST_OUT")" "spawn-args reads the tuning from the table"
pwtest_rc 0 "spawn-args empty cell" pc spawn-args --project demo --role analyst --provider cursor
pc_re '^source: native-default$' "$(cat "$PWTEST_OUT")" "empty cell resolves to the native default"
if grep -q '^arg: -m$' "$PWTEST_OUT"; then
  pwtest_bad "empty cell omits model arguments" "emitted -m for a native default"
else pwtest_ok "empty cell omits model arguments"; fi
pc_re 'reason: empty project cell' "$(cat "$PWTEST_OUT")" "empty cell states why there is no override"

# --- execution suggestions never dispatch -------------------------------------------------
pwtest_rc 0 "project execution suggestion write" pc set --project demo --key execution-suggestion --current-provider cursor --execution-provider kilo --model command_code/model --subagent pw-executor
pc_re 'cursor kilo:command_code/model' "$(pc get --project demo --key execution-suggestion 2>/dev/null)" "project suggestion reads back"
pc_mk_task demo T01 "kilo:command_code/model"
if grep -q 'Execution suggestions' "$PC/projects/demo/task/T01.md"; then
  pwtest_bad "suggestions never write task routes" "task file gained a suggestion section"
else pwtest_ok "suggestions never write task routes"; fi

# --- task execution routes ----------------------------------------------------------------
if _pc_out="$(pc set --project demo --key execution-route --task T01 --current-provider kilo --execution-provider kilo --model '—' 2>&1)"; then
  pwtest_bad "route requires a concrete model" "empty model accepted"
else
  pc_re 'target model is required' "$_pc_out" "route requires a concrete model (named refusal)"
fi
pwtest_rc 0 "route write for kilo" pc set --project demo --key execution-route --task T01 --current-provider kilo --execution-provider kilo --model command_code/model --variant high
pc_re 'kilo kilo:command_code/model' "$(pc get --project demo --key execution-route --task T01 2>/dev/null)" "route reads back"
pc_re '^- \*\*Execute with:\*\* kilo:command_code/model$' "$(grep '^- \*\*Execute with:\*\*' "$PC/projects/demo/task/T01.md")" "single route drives the derived Execute with"
pwtest_rc 0 "second route for cursor" pc set --project demo --key execution-route --task T01 --current-provider cursor --execution-provider kilo --model command_code/model
pwtest_eq "one row per current provider" "2" "$(pc get --project demo --key execution-route --task T01 | wc -l | tr -d ' ')"
pc_re '^- \*\*Execute with:\*\* multi$' "$(grep '^- \*\*Execute with:\*\*' "$PC/projects/demo/task/T01.md")" "several routes derive the multi summary"
pwtest_rc 0 "replace one route key" pc set --project demo --key execution-route --task T01 --current-provider cursor --execution-provider cursor --model cursor-test-high
pc_re 'cursor cursor:cursor-test-high' "$(pc get --project demo --key execution-route --task T01 2>/dev/null)" "replacement does not add an alternative row"
pwtest_eq "replacement keeps two unique keys" "2" "$(pc get --project demo --key execution-route --task T01 | wc -l | tr -d ' ')"
if pc set --project demo --key execution-route --task T01 --current-provider kilo --execution-provider kilo --model command_code/model --subagent not-a-worker >/dev/null 2>&1; then
  pwtest_bad "unknown target subagent refused" "not-a-worker was accepted"
else pwtest_ok "unknown target subagent refused"; fi
pwtest_rc 0 "route carries a separate subagent" pc set --project demo --key execution-route --task T01 --current-provider kilo --execution-provider kilo --model command_code/model --subagent pw-executor --variant high
pc_re 'subagent: pw-executor' "$(pc spawn-args --project demo --task T01 --current-provider kilo 2>/dev/null)" "spawn-args reports the route subagent separately"
pwtest_rc 0 "spawn-args resolves the kilo route" pc spawn-args --project demo --task T01 --current-provider kilo
pc_re '^provider: kilo$' "$(cat "$PWTEST_OUT")" "task dispatch uses the selected route"
pc_re '^model: command_code/model$' "$(cat "$PWTEST_OUT")" "task dispatch uses the route model"
pc_re '^source: task-route$' "$(cat "$PWTEST_OUT")" "task dispatch labels its source"
pwtest_rc 0 "spawn-args resolves the cursor route" pc spawn-args --project demo --task T01 --current-provider cursor
pc_re '^model: cursor-test-high$' "$(cat "$PWTEST_OUT")" "the other key resolves its own model"
if pc spawn-args --project demo --task T01 --current-provider opencode >/dev/null 2>&1; then
  pwtest_bad "missing route blocks dispatch" "opencode had no row but dispatch proceeded"
else pwtest_ok "missing route blocks dispatch"; fi
pwtest_rc 0 "route unset" pc unset --project demo --key execution-route --task T01 --current-provider cursor
pc_re 'kilo kilo:command_code/model' "$(pc get --project demo --key execution-route --task T01 2>/dev/null)" "unset removes only its key"

# A legacy pin written by an older breakdown still becomes an explicit route.
pc_mk_task demo T03 "kilo:command_code/model"
pwtest_rc 0 "route backfill preview" pc sync-routes --project demo --current-provider kilo --preview
pc_re 'T03 kilo -> kilo:command_code/model' "$(cat "$PWTEST_OUT")" "backfill preview names the derived route"
pwtest_rc 0 "route backfill" pc sync-routes --project demo --current-provider kilo
pc_re 'kilo kilo:command_code/model' "$(pc get --project demo --key execution-route --task T03 2>/dev/null)" "backfill writes the route"
pwtest_rc 0 "backfill idempotence" pc sync-routes --project demo --current-provider kilo
pc_re '0 applied' "$(cat "$PWTEST_OUT")" "a second backfill writes nothing"

# Task scope selects routes only, never project role cells.
pwtest_rc 0 "task-scope suggestion" pc suggest --project demo --task T03 --current-provider cursor \
  --set 'execution-route:T03:cursor=kilo:command_code/model'
TQ="$(cat "$PWTEST_OUT")"
pc_re 'execution-route:T03:cursor' "$TQ" "task scope lists the requested route"
if printf '%s\n' "$TQ" | grep -q 'role-model:'; then
  pwtest_bad "task scope excludes project rows" "role-model rows leaked into a task preview"
else pwtest_ok "task scope excludes project rows"; fi
TQID="$(printf '%s\n' "$TQ" | sed -n 's/.*--apply \([^ ]*\).*/\1/p' | head -1)"
pwtest_rc 0 "apply the task-scope batch" pc suggest --apply "$TQID"
pc_re 'cursor kilo:command_code/model' "$(pc get --project demo --key execution-route --task T03 2>/dev/null)" "task-scope apply writes the route"

# --- scope-aware suggestions --------------------------------------------------------------
pc_mk_task demo T02
before="$(shasum -a 256 "$R" | awk '{print $1}')"
ptask_before="$(shasum -a 256 "$PC/projects/demo/task/T01.md" | awk '{print $1}')"
pwtest_rc 0 "project suggestion preview" pc suggest --project demo
pc_eq="$(cat "$PWTEST_OUT")"
pwtest_eq "project preview never edits tasks" "$ptask_before" "$(shasum -a 256 "$PC/projects/demo/task/T01.md" | awk '{print $1}')"
pc_re 'apply: /pw-config suggest --apply' "$pc_eq" "preview returns an apply handle"
pc_re 'needs-input' "$pc_eq" "unresolved cells stay explicit"
pwtest_eq "preview writes nothing" "$before" "$(shasum -a 256 "$R" | awk '{print $1}')"
SID="$(printf '%s\n' "$pc_eq" | sed -n 's/.*--apply \([^ ]*\).*/\1/p' | head -1)"

pwtest_rc 0 "revision with an override" pc suggest --project demo \
  --set 'role-model.kilo.writer-task=command_code/model[variant=high]' \
  --exclude 'execution-suggestion:kilo'
pc_eq="$(cat "$PWTEST_OUT")"
pc_re 'role-model:kilo:writer-task' "$pc_eq" "override selects the cell"
pc_re 'explicit suggestion override' "$pc_eq" "override records why it won"
if printf '%s\n' "$pc_eq" | grep -q 'execution-suggestion:kilo'; then
  pwtest_bad "--exclude removes a row" "excluded selector still present"
else pwtest_ok "--exclude removes a row"; fi
SID2="$(printf '%s\n' "$pc_eq" | sed -n 's/.*--apply \([^ ]*\).*/\1/p' | head -1)"
if pc suggest --apply "$SID" >/dev/null 2>&1; then
  pwtest_bad "superseded proposal cannot apply" "the old preview still applied"
else pwtest_ok "superseded proposal cannot apply"; fi
pwtest_rc 0 "apply the revised batch" pc suggest --apply "$SID2"
pc_re 'kilo analyst command_code/model' "$(pc get --project demo --key role-model 2>/dev/null)" "apply writes a concrete recommendation"
pc_re 'kilo writer-task command_code/model' "$(pc get --project demo --key role-model 2>/dev/null)" "revision applies its chosen value"

# Group narrowing and an explicitly permitted replacement.
pwtest_rc 0 "group narrowing" pc suggest --project demo --group execution-suggestions
if grep -q 'role-model:' "$PWTEST_OUT"; then
  pwtest_bad "group narrowing drops other groups" "role-model rows leaked into an execution-only preview"
else pwtest_ok "group narrowing drops other groups"; fi
pwtest_rc 0 "replacement preview" pc suggest --project demo --replace-existing \
  --set 'role-model:kilo:writer-task=command_code/model[variant=low]'
pc_re 'replace' "$(cat "$PWTEST_OUT")" "replace-existing proposes a replacement over a populated cell"
RID="$(sed -n 's/.*--apply \([^ ]*\).*/\1/p' "$PWTEST_OUT" | head -1)"
pwtest_rc 0 "apply the replacement" pc suggest --apply "$RID"
pc_re 'command_code/model variant:low' "$(pc get --project demo --key role-model --provider kilo --role writer-task 2>/dev/null)" "replacement lands the new tuning"

# --- explicit migration -------------------------------------------------------------------
LM="$PC/projects/legacy"
mkdir -p "$LM/task"
cat > "$LM/README.md" <<'LEGACY'
# legacy

- **Status:** context
- **One-liner:** legacy project
- **AI Models:** researcher=kilo:command_code/model analyst=— writer-task=— reviewer=— verifier=— ship-comment-analyst=— explorer=—
- **AI Model Tuning:** researcher=variant:high
- **Project Defaults:** routing=auto execution-limit=3

## Where things are
- nothing
LEGACY
cat > "$LM/task/T01.md" <<'LEGACYTASK'
# T01: legacy task

- **Status:** todo
- **Execute with:** kilo:command_code/model
- **Route:** auto

## Goal
Legacy task.
LEGACYTASK
pwtest_rc 0 "migration preview" pc migrate --project legacy --task T01 --current-provider kilo
pc_eq="$(cat "$PWTEST_OUT")"
pc_re 'schema:project' "$pc_eq" "preview names the schema change"
pc_re 'role-model:kilo:researcher' "$pc_eq" "preview converts the legacy role row"
pc_re 'execution-route:T01:kilo' "$pc_eq" "preview converts the legacy task pin"
MID="$(printf '%s\n' "$pc_eq" | sed -n 's/.*--apply \([^ ]*\).*/\1/p' | head -1)"
pwtest_rc 0 "apply migration" pc migrate --apply "$MID"
grep -q '^- \*\*Configuration schema:\*\* 2$' "$LM/README.md" \
  && pwtest_ok "migration marks the project schema 2" \
  || pwtest_bad "migration marks the project schema 2" "marker missing"
pc_re 'kilo researcher command_code/model' "$(pc get --project legacy --key role-model 2>/dev/null)" "migration preserves the model"
pc_re 'command_code/model variant:high' "$(pc get --project legacy --key role-model --provider kilo --role researcher 2>/dev/null)" "migration preserves tuning"
pc_re 'kilo kilo:command_code/model' "$(pc get --project legacy --key execution-route --task T01 2>/dev/null)" "migration writes the explicit route"
if pc migrate --project legacy >/dev/null 2>&1; then
  pwtest_bad "re-migration is a no-op" "schema-2 project offered another conversion"
else pwtest_ok "re-migration is a no-op"; fi

# --- schema-1 backward compatibility ------------------------------------------------------
SC="$PC/projects/oldschool"
mkdir -p "$SC/task"
printf '%s\n' \
  '# oldschool' '' \
  '- **Status:** context' \
  '- **AI Models:** researcher=kilo:command_code/model analyst=— writer-task=— reviewer=— verifier=— ship-comment-analyst=— explorer=—' \
  '- **AI Model Tuning:** researcher=variant:high' '' \
  '## Where things are' > "$SC/README.md"
pwtest_rc 0 "schema-1 project still resolves a legacy role row" pc spawn-args --project oldschool --role researcher --provider kilo
pc_re '^model: command_code/model$' "$(cat "$PWTEST_OUT")" "schema-1 reads the legacy AI Models line"

# --- documentation/help surface -----------------------------------------------------------
pc_re 'role-model' "$(pc --help 2>&1 || true)" "help mentions the schema-2 keys"
