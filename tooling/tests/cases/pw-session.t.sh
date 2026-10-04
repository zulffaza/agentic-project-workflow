# shellcheck shell=bash
# cases/pw-session.t.sh — deterministic session liveness (the resume gate). Fake HOME trees +
# the tests/bin/kilo shim; no fixtures consumed on purpose (builds its own $ROOT scratch).

SES="$(pwtest_script pw-session.sh)"

# --- kilo (shim `session list --format json -a` contains ses_livetest…) ---
pwtest_rc 0 "kilo live id" env HOME="$ROOT" "$SES" session-check kilo ses_livetest0000000001
pwtest_rc 1 "kilo dead id" env HOME="$ROOT" "$SES" session-check kilo ses_dead00000000000000000000
grep -q dead "$PWTEST_ERR" && pwtest_ok "kilo dead verdict named" || pwtest_bad "kilo dead verdict" "$(head -c 120 "$PWTEST_ERR")"

# --- claude: JSONL transcripts under ~/.claude/projects/<cwd-encoded>/<id>.jsonl ---
CH="$ROOT/home-claude"; mkdir -p "$CH/.claude/projects/-some-worktree-cwd"
printf '{"type":"user"}\n' > "$CH/.claude/projects/-some-worktree-cwd/aaaa1111-2222-3333-4444-555566667777.jsonl"
: > "$CH/.claude/projects/-some-worktree-cwd/bbbb1111-2222-3333-4444-555566667777.jsonl"   # zero-byte = dead
pwtest_rc 0 "claude live transcript" env HOME="$CH" "$SES" session-check claude aaaa1111-2222-3333-4444-555566667777
pwtest_rc 1 "claude empty transcript is dead" env HOME="$CH" "$SES" session-check claude bbbb1111-2222-3333-4444-555566667777
pwtest_rc 1 "claude absent id is dead" env HOME="$CH" "$SES" session-check claude cccc1111-2222-3333-4444-555566667777
pwtest_rc 2 "claude with no projects store is unverifiable" env HOME="$ROOT/home-missing" "$SES" session-check claude aaaa1111-2222-3333-4444-555566667777

# --- cursor: ~/.cursor/chats/<hash>/<uuid>/ dirs (agent ls is NOT scriptable) ---
CU="$ROOT/home-cursor"; mkdir -p "$CU/.cursor/chats/hash1/deadbeef-0000-1111-2222-333344445555"
pwtest_rc 0 "cursor live chat dir" env HOME="$CU" "$SES" session-check cursor deadbeef-0000-1111-2222-333344445555
pwtest_rc 1 "cursor absent uuid is dead" env HOME="$CU" "$SES" session-check cursor 11112222-3333-4444-5555-666677778888
pwtest_rc 2 "cursor with no chats store is unverifiable" env HOME="$ROOT/home-missing" "$SES" session-check cursor deadbeef-0000-1111-2222-333344445555

# --- codex: rollout files ~/.codex/sessions/<Y>/<M>/<D>/rollout-<ts>-<thread-id>.jsonl (the
# thread_id from `codex exec --json`'s thread.started event is embedded in the FILENAME —
# probe-verified 2026-10-04 on codex-cli 0.160.0; zero-byte rollout = dead, claude's stance) ---
CX="$ROOT/home-codex"; mkdir -p "$CX/.codex/sessions/2026/10/04"
printf '{"type":"event_msg"}\n' > "$CX/.codex/sessions/2026/10/04/rollout-2026-10-04T22-02-07-01a1076f-c2a2-7512-85bb-4edb1bb67e0a.jsonl"
: > "$CX/.codex/sessions/2026/10/04/rollout-2026-10-04T22-03-00-01a1076f-0000-1111-2222-333344445555.jsonl"
pwtest_rc 0 "codex live rollout" env HOME="$CX" "$SES" session-check codex 01a1076f-c2a2-7512-85bb-4edb1bb67e0a
pwtest_rc 1 "codex empty rollout is dead" env HOME="$CX" "$SES" session-check codex 01a1076f-0000-1111-2222-333344445555
pwtest_rc 1 "codex absent id is dead" env HOME="$CX" "$SES" session-check codex 99999999-0000-0000-0000-000000000000
pwtest_rc 2 "codex with no sessions store is unverifiable" env HOME="$ROOT/home-missing" "$SES" session-check codex 01a1076f-c2a2-7512-85bb-4edb1bb67e0a

# --- conservative readings: opencode (no verified surface yet) + unknown provider ---
pwtest_rc 2 "opencode unverifiable (never a false live)" env HOME="$ROOT" "$SES" session-check opencode ses_anything
grep -qE 'unverifiable|probe' "$PWTEST_ERR" && pwtest_ok "opencode note names the probe path" || pwtest_bad "opencode note" "$(head -c 120 "$PWTEST_ERR")"
pwtest_rc 2 "unknown provider unverifiable" env HOME="$ROOT" "$SES" session-check kilotest ses_anything

# --- task-file form: provider + id come from the task, never transcribed ---
TP="$ROOT/projects/sessdemo"; mkdir -p "$TP/task"
printf -- '- **Execute with:** kilo:alibaba-token-plan/test-model\n- **Session:** ses_livetest0000000001\n' > "$TP/task/T01.md"
printf -- '- **Execute with:** kilo:alibaba-token-plan/test-model\n- **Session:** —\n' > "$TP/task/T02.md"
pwtest_rc 0 "task form reads the live id off the file" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check sessdemo T01
pwtest_rc 1 "task form: sentinel Session is dead (no id to try)" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check sessdemo T02
pwtest_rc 2 "task form: unknown task file refused" env HOME="$ROOT" PW_PROJECTS_DIR="$ROOT/projects" "$SES" session-check sessdemo T99
pwtest_fix "unknown task carries a fix"

# --- --help / usage shape (registry duty) ---
pwtest_rc 0 "session-check --help" "$SES" --help
