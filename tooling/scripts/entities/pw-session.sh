#!/usr/bin/env bash
# ============================================================================
# pw-session.sh — deterministic headless-session liveness (the resume gate)
#
#   pw-session.sh session-check --provider <provider> --session <session-id>
#   pw-session.sh session-check --project <slug> --task <task-id>
#       Is the recorded session still resumable? exit 0 = live, 1 = dead/absent,
#       2 = unverifiable (provider without a checked surface, or its store not
#       reachable). The 2-reading on the ladder is conservative: NOT resumable →
#       cold/inline path; never a false "live".
#       The --project/--task form reads the provider + `- **Session:**` id from
#       the task file, so the driver never transcribes ids.
#
# Named-argument grammar: operation words first, every value named; --project
# selects the project. Scalar values are ONE token (quote spaces).
#
# Per-provider surface (probe-verified 2026-09-23 on this machine):
#   kilo     — `kilo session list --format json -a`, id present in the output
#   claude   — file ~/.claude/projects/<cwd-encoded>/<id>.jsonl (searched across
#              ALL project dirs — a worktree maps to a different encoding; a
#              zero-byte file counts as dead)
#   cursor   — dir ~/.cursor/chats/<workspace-hash>/<chat-uuid>/ (the uuid is the
#              `--resume` handle; `agent ls` is an interactive TUI, NOT scriptable)
#   codex    — rollout file ~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<thread-id>.jsonl
#              (the thread_id from `codex exec --json`'s thread.started event is embedded
#              in the FILENAME; resume handle = `codex exec resume <thread-id>`).
#              Probe-verified 2026-10-04 on codex-cli 0.160.0.
#   opencode — no verified surface yet (CLI absent on the probe machine): always 2
#              with the probe hint. Verified elsewhere? Implement it HERE, not in
#              callers — the ladder asks this script, never a CLI, "is it live".
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
case "${1:-}" in -h|--help) pw_usage ;; esac

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"

die() { echo "pw-session: $*" >&2; exit 2; }

# _sc_kilo <id> — 0 live / 1 dead / 2 unverifiable
_sc_kilo() {
  local id="$1" out
  declare -f kilo_bin >/dev/null 2>&1 || return 2
  local bin; bin="$(kilo_bin)"
  command -v "$bin" >/dev/null 2>&1 || return 2
  out="$("$bin" session list --format json -a 2>/dev/null)" || return 2
  printf '%s' "$out" | grep -qF "$id" && { echo "session-check: kilo:$id — live (in '$bin session list --format json -a')"; return 0; }
  echo "session-check: kilo:$id — dead (not in '$bin session list --format json -a') → fix: take the ladder's cold path (seed-patched re-spawn)" >&2
  return 1
}

# _sc_claude <id> — JSONL transcript under ~/.claude/projects/*/<id>.jsonl
_sc_claude() {
  local id="$1" f found=0
  [ -d "$HOME/.claude/projects" ] || return 2
  for f in "$HOME/.claude/projects"/*/"$id".jsonl; do
    [ -e "$f" ] || continue
    found=1
    if [ -s "$f" ]; then echo "session-check: claude:$id — live ($f)"; return 0; fi
  done
  if [ "$found" = 1 ]; then echo "session-check: claude:$id — dead (transcript present but empty/rotated) → fix: take the ladder's cold path (seed-patched re-spawn)" >&2; return 1; fi
  echo "session-check: claude:$id — dead (no transcript under ~/.claude/projects) → fix: take the ladder's cold path (seed-patched re-spawn)" >&2
  return 1
}

# _sc_cursor <id> — chat dir under ~/.cursor/chats/<hash>/<id>/
_sc_cursor() {
  local d found=0
  [ -d "$HOME/.cursor/chats" ] || return 2
  for d in "$HOME/.cursor/chats"/*/"$1"; do
    [ -d "$d" ] || continue
    found=1
    echo "session-check: cursor:$1 — live ($d)"; return 0
  done
  if [ "$found" = 1 ]; then echo "session-check: cursor:$1 — dead → fix: take the ladder's cold path (seed-patched re-spawn)" >&2; return 1; fi
  echo "session-check: cursor:$1 — dead (no chat dir under ~/.cursor/chats) → fix: take the ladder's cold path (seed-patched re-spawn)" >&2
  return 1
}

# _sc_codex <thread-id> — rollout JSONL whose FILENAME embeds the id, under
# ~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-<ts>-<thread-id>.jsonl (a zero-byte file counts
# as dead, same stance as claude's transcript check).
_sc_codex() {
  local id="$1" f found=0
  [ -d "$HOME/.codex/sessions" ] || return 2
  for f in "$HOME"/.codex/sessions/*/*/*/*"$id"*.jsonl; do
    [ -e "$f" ] || continue
    found=1
    if [ -s "$f" ]; then echo "session-check: codex:$id — live ($f)"; return 0; fi
  done
  if [ "$found" = 1 ]; then echo "session-check: codex:$id — dead (rollout present but empty) → fix: take the ladder's cold path (seed-patched re-spawn)" >&2; return 1; fi
  echo "session-check: codex:$id — dead (no rollout under ~/.codex/sessions) → fix: take the ladder's cold path (seed-patched re-spawn)" >&2
  return 1
}

cmd_session_check() {
  local prov="" sid="" slug="" task="" id="" rc=0 a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --provider=*) v="${a#*=}"; a="--provider" ;;
      --session=*)  v="${a#*=}"; a="--session" ;;
      --project=*)  v="${a#*=}"; a="--project" ;;
      --task=*)     v="${a#*=}"; a="--task" ;;
    esac
    case "$a" in
      --provider|--session|--project|--task)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in
          --provider) prov="$v" ;;
          --session)  sid="$v" ;;
          --project)  slug="$v" ;;
          --task)     task="$v" ;;
        esac ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "session-check --provider <p> --session <id> | session-check --project <slug> --task <T0n>" ;;
      *) _pw_positional "$a" "session-check --provider <p> --session <id> | session-check --project <slug> --task <T0n>" ;;
    esac
  done

  # Two dispatch forms, same liveness answer. Task form: provider + id come from the task
  # file (never transcribed by the caller). Provider form: both values are given directly.
  # A mixed pair fails closed instead of guessing which form was meant.
  if [ -n "$slug" ] || [ -n "$task" ]; then
    [ -n "$slug" ] && [ -n "$task" ] || die "session-check: --project and --task go together → fix: session-check --project <slug> --task <T0n>"
    if [ -n "$prov" ] || [ -n "$sid" ]; then
      die "session-check: --provider/--session cannot combine with --project/--task → fix: pass one form"
    fi
    pw_proj_slug_ok "$slug" || die "session-check: invalid project slug '$slug' → fix: use one project directory name"
    pw_task_id_ok "$task" || die "session-check: invalid task id '$task' → fix: task ids look like T01"
    local tf; tf="$PROJECTS_DIR/$slug/task/$task.md"
    [ -f "$tf" ] || die "no task file: $slug/task/$task.md → fix: check the task id (or pass --provider <p> --session <id> directly)"
    local sess exec_with _keys _cur
    sess="$(pw_field "$tf" Session || true)"
    case "${sess:-}" in ""|"—"|"<*") echo "session-check: $slug/$task — dead (no recorded Session: id)" >&2; return 1 ;; esac
    if [ "$(pw_task_schema "$tf")" = 2 ]; then
      _cur="${PW_CURRENT_PROVIDER:-}"
      if [ -n "$_cur" ]; then
        local _row; _row="$(pw_task_route_row "$tf" "$_cur" 2>/dev/null || true)"
        if [ -z "$_row" ]; then
          echo "session-check: $slug/$task — not resumable (no execution route for current provider '$_cur') → fix: add the route before resuming" >&2
          return 1
        fi
        prov="${_row%%$'\t'*}"
      else
        _keys="$(pw_task_route_keys "$tf" | awk 'NF')"
        if [ "$(printf '%s\n' "$_keys" | wc -l | tr -d ' ')" != 1 ]; then
          echo "session-check: $slug/$task — not resumable (several current-provider routes; set PW_CURRENT_PROVIDER or pass --provider directly)" >&2
          return 1
        fi
        _row="$(pw_task_route_row "$tf" "$_keys" 2>/dev/null || true)"
        prov="${_row%%$'\t'*}"
      fi
      [ -n "$prov" ] || { echo "session-check: $slug/$task — not resumable (route has no execution provider)" >&2; return 1; }
    else
      exec_with="$(pw_field "$tf" "Execute with" || true)"
      prov="${exec_with%%:*}"
    fi
    id="$sess"
  else
    [ -n "$prov" ] || die "session-check: --provider is required → fix: session-check --provider <p> --session <id> | session-check --project <slug> --task <T0n>"
    [ -n "$sid" ] || die "session-check: --session is required → fix: session-check --provider <p> --session <id>"
    id="$sid"
  fi
  # The id is globbed into transcript paths (~/.claude/projects/*/<id>.jsonl, …); keep it a
  # plain token so `../` can never walk the probe outside those roots.
  case "$id" in ''|*[!A-Za-z0-9._-]*) echo "session-check: invalid session id '$id' → fix: pass the provider's session/thread id (letters, digits, dot, dash, underscore)" >&2; return 1 ;; esac
  case "$prov" in
    kilo)     _sc_kilo "$id"   ;;
    claude)   _sc_claude "$id" ;;
    cursor)   _sc_cursor "$id" ;;
    codex)    _sc_codex "$id"  ;;
    opencode) echo "session-check: opencode:$id — unverifiable (no checked liveness surface) → fix: probe \`opencode\` on a machine that has it and implement the check here (session-check), not in callers; until then treat as not-resumable" >&2; rc=2 ;;
    *)        echo "session-check: $prov:$id — unverifiable (unknown provider '$prov') → fix: run --help for the supported providers" >&2; rc=2 ;;
  esac
  return $rc
}

case "${1:-}" in
  session-check) shift; cmd_session_check "$@"; exit $? ;;
  *) die "usage: pw-session.sh <session-check> … (see --help)" ;;
esac
