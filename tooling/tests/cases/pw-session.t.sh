# shellcheck shell=bash
# cases/pw-session.t.sh — deterministic session liveness (the resume gate). Fake HOME trees +
# the tests/bin/kilo shim; no fixtures consumed on purpose (builds its own $ROOT scratch).

SES="$(pwtest_script pw-session.sh)"

# --- kilo (shim `session list --format json -a` contains ses_livetest…) ---
pwtest_rc 0 "kilo live id" env HOME="$ROOT" "$SES" session-check --provider kilo --session ses_livetest0000000001
pwtest_rc 1 "kilo dead id" env HOME="$ROOT" "$SES" session-check --provider kilo --session ses_dead00000000000000000000
grep -q dead "$PWTEST_ERR" && pwtest_ok "kilo dead verdict named" || pwtest_bad "kilo dead verdict" "$(head -c 120 "$PWTEST_ERR")"

# --- claude: JSONL transcripts under ~/.claude/projects/<cwd-encoded>/<id>.jsonl ---
CH="$ROOT/home-claude"; mkdir -p "$CH/.claude/projects/-some-worktree-cwd"
printf '{"type":"user"}\n' > "$CH/.claude/projects/-some-worktree-cwd/aaaa1111-2222-3333-4444-555566667777.jsonl"
: > "$CH/.claude/projects/-some-worktree-cwd/bbbb1111-2222-3333-4444-555566667777.jsonl"   # zero-byte = dead
pwtest_rc 0 "claude live transcript" env HOME="$CH" "$SES" session-check --provider claude --session aaaa1111-2222-3333-4444-555566667777
pwtest_rc 1 "claude empty transcript is dead" env HOME="$CH" "$SES" session-check --provider claude --session bbbb1111-2222-3333-4444-555566667777
pwtest_rc 1 "claude absent id is dead" env HOME="$CH" "$SES" session-check --provider claude --session cccc1111-2222-3333-4444-555566667777
pwtest_rc 2 "claude with no projects store is unverifiable" env HOME="$ROOT/home-missing" "$SES" session-check --provider claude --session aaaa1111-2222-3333-4444-555566667777

# --- cursor: ~/.cursor/chats/<hash>/<uuid>/ dirs (agent ls is NOT scriptable) ---
CU="$ROOT/home-cursor"; mkdir -p "$CU/.cursor/chats/hash1/deadbeef-0000-1111-2222-333344445555"
pwtest_rc 0 "cursor live chat dir" env HOME="$CU" "$SES" session-check --provider cursor --session deadbeef-0000-1111-2222-333344445555
pwtest_rc 1 "cursor absent uuid is dead" env HOME="$CU" "$SES" session-check --provider cursor --session 11112222-3333-4444-5555-666677778888
pwtest_rc 2 "cursor with no chats store is unverifiable" env HOME="$ROOT/home-missing" "$SES" session-check --provider cursor --session deadbeef-0000-1111-2222-333344445555

# --- codex: rollout files ~/.codex/sessions/<Y>/<M>/<D>/rollout-<ts>-<thread-id>.jsonl (the
# thread_id from `codex exec --json`'s thread.started event is embedded in the FILENAME —
# probe-verified 2026-10-04 on codex-cli 0.160.0; zero-byte rollout = dead, claude's stance) ---
CX="$ROOT/home-codex"; mkdir -p "$CX/.codex/sessions/2026/10/04"
printf '{"type":"event_msg"}\n' > "$CX/.codex/sessions/2026/10/04/rollout-2026-10-04T22-02-07-01a1076f-c2a2-7512-85bb-4edb1bb67e0a.jsonl"
: > "$CX/.codex/sessions/2026/10/04/rollout-2026-10-04T22-03-00-01a1076f-0000-1111-2222-333344445555.jsonl"
pwtest_rc 0 "codex live rollout" env HOME="$CX" "$SES" session-check --provider codex --session 01a1076f-c2a2-7512-85bb-4edb1bb67e0a
pwtest_rc 1 "codex empty rollout is dead" env HOME="$CX" "$SES" session-check --provider codex --session 01a1076f-0000-1111-2222-333344445555
pwtest_rc 1 "codex absent id is dead" env HOME="$CX" "$SES" session-check --provider codex --session 99999999-0000-0000-0000-000000000000
pwtest_rc 2 "codex with no sessions store is unverifiable" env HOME="$ROOT/home-missing" "$SES" session-check --provider codex --session 01a1076f-c2a2-7512-85bb-4edb1bb67e0a

# --- muse: date-sharded store ~/.local/share/muse/sessions/<Y>/<M>/<D>/<uuid>/session.jsonl
# (the id is deterministic per run via `muse exec --session-id`; reuse continues context;
# `muse resume` is interactive-only — probe-verified 2026-11-05 on muse 1.4.14) ---
MU="$ROOT/home-muse"; mkdir -p "$MU/.local/share/muse/sessions/2026/11/05/01a1ac1a-7f39-7621-b4bb-8f48bc6399bb"
printf '{"kind":"session_init"}\n' > "$MU/.local/share/muse/sessions/2026/11/05/01a1ac1a-7f39-7621-b4bb-8f48bc6399bb/session.jsonl"
mkdir -p "$MU/.local/share/muse/sessions/2026/11/05/02a1ac1a-7f39-7621-b4bb-8f48bc6399cc"
: > "$MU/.local/share/muse/sessions/2026/11/05/02a1ac1a-7f39-7621-b4bb-8f48bc6399cc/session.jsonl"
pwtest_rc 0 "muse live session.jsonl" env HOME="$MU" "$SES" session-check --provider muse --session 01a1ac1a-7f39-7621-b4bb-8f48bc6399bb
grep -q live "$PWTEST_OUT" && pwtest_ok "muse live verdict named" || pwtest_bad "muse live verdict" "$(head -c 120 "$PWTEST_OUT")"
pwtest_rc 1 "muse empty session.jsonl is dead" env HOME="$MU" "$SES" session-check --provider muse --session 02a1ac1a-7f39-7621-b4bb-8f48bc6399cc
pwtest_rc 1 "muse absent id is dead" env HOME="$MU" "$SES" session-check --provider muse --session 99999999-0000-0000-0000-000000000000
grep -q dead "$PWTEST_ERR" && pwtest_ok "muse dead verdict named" || pwtest_bad "muse dead verdict" "$(head -c 120 "$PWTEST_ERR")"
pwtest_rc 2 "muse with no sessions store is unverifiable" env HOME="$ROOT/home-missing" "$SES" session-check --provider muse --session 01a1ac1a-7f39-7621-b4bb-8f48bc6399bb
# --- muse task-file form: bare id (no suffix syntax), hermetic catalog fixture ---
MUCAT="$ROOT/muse-catalog"; mkdir -p "$MUCAT"
cat > "$MUCAT/cache.json" <<'JSON'
{"schema_version": 2, "provider_id": "meta", "rows": [
{"model_id": "muse-test-flash", "visibility": "visible", "context_limit": 1007997, "output_limit": 128000, "reasoning_effort_variants": [{"tier": "low"}]}
]}
JSON
TPM="$ROOT/projects/sessmuse"; mkdir -p "$TPM/task"
printf -- '- **Execute with:** muse:muse-test-flash\n- **Session:** 01a1ac1a-7f39-7621-b4bb-8f48bc6399bb\n' > "$TPM/task/T01.md"
pwtest_rc 0 "task form reads the muse live id off the file" env HOME="$MU" PW_MUSE_CATALOG_DIR="$MUCAT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project sessmuse --task T01

# --- opencode: `session export --sanitize <id>` (shim mirrors the real 2.2.5 shape: JSON on
# stdout = live, "Session not found" on stderr = dead, exit 0 either way) ---
pwtest_rc 0 "opencode live session" env HOME="$ROOT" "$SES" session-check --provider opencode --session ses_livetest0000000000000001
grep -q live "$PWTEST_OUT" && pwtest_ok "opencode live verdict named" || pwtest_bad "opencode live verdict" "$(head -c 120 "$PWTEST_OUT")"
pwtest_rc 1 "opencode absent id is dead" env HOME="$ROOT" "$SES" session-check --provider opencode --session ses_dead00000000000000000000
grep -q dead "$PWTEST_ERR" && pwtest_ok "opencode dead verdict named" || pwtest_bad "opencode dead verdict" "$(head -c 120 "$PWTEST_ERR")"
pwtest_rc 2 "opencode with no CLI is unverifiable" env HOME="$ROOT" PATH=/usr/bin:/bin "$SES" session-check --provider opencode --session ses_livetest0000000000000001

# --- conservative readings: unknown provider ---
pwtest_rc 2 "unknown provider unverifiable" env HOME="$ROOT" "$SES" session-check --provider kilotest --session ses_anything

# --- task-file form: provider + id come from the task, never transcribed ---
TP="$ROOT/projects/sessdemo"; mkdir -p "$TP/task"
printf -- '- **Execute with:** kilo:alibaba-token-plan/test-model\n- **Session:** ses_livetest0000000001\n' > "$TP/task/T01.md"
printf -- '- **Execute with:** kilo:alibaba-token-plan/test-model\n- **Session:** —\n' > "$TP/task/T02.md"
pwtest_rc 0 "task form reads the live id off the file" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project sessdemo --task T01
pwtest_rc 1 "task form: sentinel Session is dead (no id to try)" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project sessdemo --task T02
pwtest_rc 2 "task form: unknown task file refused" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project sessdemo --task T99
pwtest_fix "unknown task carries a fix"

# --- schema-2 identity: liveness alone never authorizes a resume ---------------------------
TP2="$ROOT/projects/routed"; mkdir -p "$TP2/task"
cat > "$TP2/task/T01.md" <<'TASK'
- **Session:** ses_livetest0000000001
- **Actually used:** kilo:alibaba-token-plan/test-model --variant high

## Execution routes

| Current provider | Execution provider | Target model | Target subagent | Variant | Reasoning | Effort | Thinking |
|---|---|---|---|---|---|---|---|
| kilo | kilo | alibaba-token-plan/test-model | — | high | — | — | — |
TASK
pwtest_rc 0 "recorded identity matches the resolved route" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project routed --task T01
sed -i.bak -e 's/--variant high/--variant low/' "$TP2/task/T01.md"; rm -f "$TP2/task/T01.md.bak"
pwtest_rc 1 "changed tuning blocks resume" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project routed --task T01
grep -q 'variant' "$PWTEST_ERR" && pwtest_ok "changed-tuning refusal names the mismatch" || pwtest_bad "changed-tuning refusal" "$(head -c 160 "$PWTEST_ERR")"
sed -i.bak -e 's/^- \*\*Actually used:\*\* .*/- **Actually used:** <filled by the orchestrator at run time>/' "$TP2/task/T01.md"; rm -f "$TP2/task/T01.md.bak"
pwtest_rc 1 "missing recorded identity blocks resume" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project routed --task T01
grep -q 'no recorded attempt identity' "$PWTEST_ERR" && pwtest_ok "missing-identity refusal is explicit" || pwtest_bad "missing-identity refusal" "$(head -c 160 "$PWTEST_ERR")"

# --- opencode schema-2 identity: the #level suffix in Actually-used matches the route's
# bare model + Variant column (the shim LIVE_ID is the opencode session shape) ---
cat > "$TP2/task/T02.md" <<'TASK'
- **Session:** ses_livetest0000000000000001
- **Actually used:** opencode:testprov/test-model#low

## Execution routes

| Current provider | Execution provider | Target model | Target subagent | Variant | Reasoning | Effort | Thinking |
|---|---|---|---|---|---|---|---|
| opencode | opencode | testprov/test-model | — | low | — | — | — |
TASK
pwtest_rc 0 "opencode suffixed identity matches the bare route + variant" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project routed --task T02
sed -i.bak -e 's/opencode:testprov\/test-model#low/opencode:testprov\/test-model#high/' "$TP2/task/T02.md"; rm -f "$TP2/task/T02.md.bak"
pwtest_rc 1 "opencode changed variant blocks resume" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project routed --task T02
grep -q 'variant' "$PWTEST_ERR" && pwtest_ok "opencode changed-variant refusal names the mismatch" || pwtest_bad "opencode changed-variant refusal" "$(head -c 160 "$PWTEST_ERR")"
sed -i.bak -e 's/opencode:testprov\/test-model#high/opencode:testprov\/test-model#/' "$TP2/task/T02.md"; rm -f "$TP2/task/T02.md.bak"
pwtest_rc 1 "opencode malformed suffix blocks resume" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project routed --task T02

# --- muse schema-2 identity: the --reasoning-effort headless flag in Actually-used matches
# the route's Effort column (plan 67: the parser's only muse-specific flag reading) ---
cat > "$TP2/task/T03.md" <<'TASK'
- **Execute with:** muse:muse-test-flash
- **Effort:** max
- **Session:** 01a1ac1a-7f39-7621-b4bb-8f48bc6399bb
- **Actually used:** muse:muse-test-flash --reasoning-effort max

## Execution routes

| Current provider | Execution provider | Target model | Target subagent | Variant | Reasoning | Effort | Thinking |
|---|---|---|---|---|---|---|---|
| muse | muse | muse-test-flash | — | — | — | max | — |
TASK
pwtest_rc 0 "muse reasoning-effort identity matches the route effort" env HOME="$MU" PW_MUSE_CATALOG_DIR="$MUCAT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project routed --task T03
sed -i.bak -e 's/--reasoning-effort max/--reasoning-effort low/' "$TP2/task/T03.md"; rm -f "$TP2/task/T03.md.bak"
pwtest_rc 1 "muse changed effort blocks resume" env HOME="$MU" PW_MUSE_CATALOG_DIR="$MUCAT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check --project routed --task T03
grep -q 'effort' "$PWTEST_ERR" && pwtest_ok "muse changed-effort refusal names the mismatch" || pwtest_bad "muse changed-effort refusal" "$(head -c 160 "$PWTEST_ERR")"

# --- --help / usage shape (registry duty) ---
pwtest_rc 0 "session-check --help" "$SES" --help
