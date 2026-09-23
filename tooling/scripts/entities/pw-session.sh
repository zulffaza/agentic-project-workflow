#!/usr/bin/env bash
# ============================================================================
# pw-session.sh — deterministic headless-session liveness (the resume gate)
#
#   pw-session.sh session-check <provider> <session-id>
#   pw-session.sh session-check <slug> <task-id>
#       Is the recorded session still resumable? exit 0 = live, 1 = dead/absent,
#       2 = unverifiable (provider without a checked surface, or its store not
#       reachable). The 2-reading on the ladder is conservative: NOT resumable →
#       cold/inline path; never a false "live".
#       The <slug> <task-id> form reads the provider + `- **Session:**` id from
#       the task file, so the driver never transcribes ids.
#
# Per-provider surface (probe-verified 2026-09-23 on this machine):
#   kilo     — `kilo session list --format json -a`, id present in the output
#   claude   — file ~/.claude/projects/<cwd-encoded>/<id>.jsonl (searched across
#              ALL project dirs — a worktree maps to a different encoding; a
#              zero-byte file counts as dead)
#   cursor   — dir ~/.cursor/chats/<workspace-hash>/<chat-uuid>/ (the uuid is the
#              `--resume` handle; `agent ls` is an interactive TUI, NOT scriptable)
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

cmd_session_check() {
  [ $# -eq 2 ] || die "usage: session-check <provider> <session-id> | session-check <slug> <task-id>"
  local prov="$1" id="$2" rc=0
  # slug/task form: provider + id come from the task file (never transcribed by the caller)
  if [ -d "$PROJECTS_DIR/$prov" ] && printf '%s' "$id" | grep -qE '^T[0-9]+$'; then
    local slug="$prov" tf; tf="$PROJECTS_DIR/$slug/task/$id.md"
    [ -f "$tf" ] || die "no task file: $slug/task/$id.md → fix: check the task id (or pass <provider> <session-id> directly)"
    local sess exec_with
    sess="$(pw_field "$tf" Session || true)"
    case "${sess:-}" in ""|"—"|"<*") echo "session-check: $slug/$id — dead (no recorded Session: id)" >&2; return 1 ;; esac
    exec_with="$(pw_field "$tf" "Execute with" || true)"
    prov="${exec_with%%:*}"
    id="$sess"
  fi
  case "$prov" in
    kilo)     _sc_kilo "$id"   ;;
    claude)   _sc_claude "$id" ;;
    cursor)   _sc_cursor "$id" ;;
    opencode) echo "session-check: opencode:$id — unverifiable (no checked liveness surface) → fix: probe \`opencode\` on a machine that has it and implement it in pw-session.sh, not in callers; until then treat as not-resumable" >&2; rc=2 ;;
    *)        echo "session-check: $prov:$id — unverifiable (unknown provider '$prov') → fix: run --help for the supported providers" >&2; rc=2 ;;
  esac
  return $rc
}

case "${1:-}" in
  session-check) shift; cmd_session_check "$@"; exit $? ;;
  *) die "usage: pw-session.sh <session-check> … (see --help)" ;;
esac
