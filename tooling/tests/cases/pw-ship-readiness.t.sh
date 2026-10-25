# shellcheck shell=bash
# cases/pw-ship-readiness.t.sh — draft readiness: read-only preview, freshness-bound apply,
# both directions, existing-MR preservation, interrupted-attempt resume, lock exclusion,
# GitHub native readiness, and draft creation readback.
SH=pw-ship.sh
export PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.readiness.sh"
export PWTEST_GH_TITLE_FILE="$ROOT/gh-titles"; : > "$PWTEST_GH_TITLE_FILE"
P=rdy; rm -rf "$PW_PROJECTS_DIR/$P"; cp -a "$F2" "$PW_PROJECTS_DIR/$P"
export PWTEST_MR_TITLE_FILE="$ROOT/rdy-titles"; : > "$PWTEST_MR_TITLE_FILE"
printf '42 Fixture MR\n' >> "$PWTEST_MR_TITLE_FILE"
export PWTEST_GH_DRAFT_FILE="$ROOT/gh-draft"; : > "$PWTEST_GH_DRAFT_FILE"
: > "$PWTEST_FORGE_STATE_FILE"; printf '42 opened\n' >> "$PWTEST_FORGE_STATE_FILE"

# --- preview is read-only -----------------------------------------------------
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "preview draft" "$(pwtest_script $SH)" draft --project "$P" --task T02
pwtest_re '^T02\|.*\|ready\|draft\|change$' "preview shows the direction"
TOKEN="$(sed -n 's/^token: //p' "$PWTEST_OUT")"
[ -n "$TOKEN" ] && pwtest_ok "preview prints an expectation token" || pwtest_bad "token" "missing"
if grep -q -- '--method PUT' "$PWTEST_FORGE_LOG"; then pwtest_bad "preview purity" "preview wrote to the forge"; else pwtest_ok "preview performed no forge write"; fi
[ ! -e "$PW_PROJECTS_DIR/$P/task/ship-readiness" ] && pwtest_ok "preview wrote no journal" || pwtest_bad "preview journal" "journal created"

# --- only open MRs are eligible -------------------------------------------------
printf '42 merged\n' > "$PWTEST_FORGE_STATE_FILE"
pwtest_rc 2 "merged MR refused" "$(pwtest_script $SH)" draft --project "$P" --task T02
pwtest_err 'merged|open MR' "merged refusal is explicit"
printf '42 closed\n' > "$PWTEST_FORGE_STATE_FILE"
pwtest_rc 2 "closed MR refused" "$(pwtest_script $SH)" ready --project "$P" --task T02
printf '42 opened\n' > "$PWTEST_FORGE_STATE_FILE"

# --- apply refuses stale tokens before any write ------------------------------
: > "$PWTEST_FORGE_LOG"
pwtest_rc 2 "stale token refused" "$(pwtest_script $SH)" draft --project "$P" --task T02 --apply --expect deadbeef
pwtest_err 'fresh preview' "stale token names the fix"
grep -q -- '--method PUT' "$PWTEST_FORGE_LOG" && pwtest_bad "stale token write" "forge was called" || pwtest_ok "stale token wrote nothing"

# --- apply draft, then promote back -------------------------------------------
pwtest_rc 0 "apply draft" "$(pwtest_script $SH)" draft --project "$P" --task T02 --apply --expect "$TOKEN"
pwtest_re 'T02\|.*\|ready\|draft\|confirmed' "draft confirmed"
pwtest_rc 0 "inspect after draft" "$(pwtest_script $SH)" draft --project "$P" --task T02
pwtest_re '\|draft\|draft\|noop' "preview now reads draft"
grep -q '^42 Draft: Fixture MR$' "$PWTEST_MR_TITLE_FILE" && pwtest_ok "title gained the draft marker" || pwtest_bad "title" "$(cat "$PWTEST_MR_TITLE_FILE")"
grep -q 'readiness draft confirmed' "$PW_PROJECTS_DIR/$P/LOG.md" && pwtest_ok "transition recorded in LOG" || pwtest_bad "log" "missing draft transition"

pwtest_rc 0 "preview ready" "$(pwtest_script $SH)" ready --project "$P" --task T02
TOKEN2="$(sed -n 's/^token: //p' "$PWTEST_OUT")"
pwtest_rc 0 "apply ready" "$(pwtest_script $SH)" ready --project "$P" --task T02 --apply --expect "$TOKEN2"
pwtest_re 'T02\|.*\|draft\|ready\|confirmed' "ready confirmed"
grep -q '^42 Fixture MR$' "$PWTEST_MR_TITLE_FILE" && pwtest_ok "title marker removed" || pwtest_bad "title" "$(cat "$PWTEST_MR_TITLE_FILE")"

# --- repeat transition is a no-op (fresh preview, no forge write) -------------
pwtest_rc 0 "preview ready again" "$(pwtest_script $SH)" ready --project "$P" --task T02
pwtest_re 'noop' "preview reports noop"
TOKEN3="$(sed -n 's/^token: //p' "$PWTEST_OUT")"
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "apply noop" "$(pwtest_script $SH)" ready --project "$P" --task T02 --apply --expect "$TOKEN3"
pwtest_re 'summary: 0 confirmed, 1 noop' "noop summary"
grep -q -- '--method PUT' "$PWTEST_FORGE_LOG" && pwtest_bad "noop write" "forge called" || pwtest_ok "noop wrote nothing"

# --- lock exclusion -----------------------------------------------------------
mkdir -p "$PW_PROJECTS_DIR/$P/task/ship-readiness/.lock"
printf '{"pid":%d,"host":"%s","started":0}\n' "$$" "$(hostname)" > "$PW_PROJECTS_DIR/$P/task/ship-readiness/.lock/owner.json"
pwtest_rc 0 "preview before lock test" "$(pwtest_script $SH)" draft --project "$P" --task T02
LOCKTOKEN="$(sed -n 's/^token: //p' "$PWTEST_OUT")"
pwtest_rc 2 "live lock blocks apply" "$(pwtest_script $SH)" draft --project "$P" --task T02 --apply --expect "$LOCKTOKEN"
pwtest_err 'readiness apply holds|lock' "lock names the conflict"
rm -rf "$PW_PROJECTS_DIR/$P/task/ship-readiness/.lock"

# --- interrupted-attempt resume reconciles without another write --------------
pwtest_rc 0 "preview before resume" "$(pwtest_script $SH)" draft --project "$P" --task T02
TOKEN4="$(sed -n 's/^token: //p' "$PWTEST_OUT")"
pwtest_rc 0 "apply before resume" "$(pwtest_script $SH)" draft --project "$P" --task T02 --apply --expect "$TOKEN4"
ATTEMPT="$(sed -n 's/^readiness apply: draft attempt=//p' "$PWTEST_OUT")"
J="$PW_PROJECTS_DIR/$P/task/ship-readiness/$ATTEMPT.json"
python3 - "$J" <<'PYJ'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for e in d['entries']:
    e['status'] = 'write-uncertain'; e['logged'] = False; e['observed'] = ''
d['status'] = 'stopped'
json.dump(d, open(p, 'w'), indent=2)
PYJ
pwtest_rc 0 "preview while an attempt is unresolved" "$(pwtest_script $SH)" ready --project "$P" --task T02
BLOCKTOKEN="$(sed -n 's/^token: //p' "$PWTEST_OUT")"
pwtest_rc 2 "fresh apply refuses an unresolved attempt" "$(pwtest_script $SH)" ready --project "$P" --task T02 --apply --expect "$BLOCKTOKEN"
pwtest_err 'unresolved readiness attempt|--resume' "unresolved attempt names resume"
BEFORE="$(grep -c 'readiness draft confirmed' "$PW_PROJECTS_DIR/$P/LOG.md" || true)"
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "resume reconciles" "$(pwtest_script $SH)" draft --project "$P" --task T02 --apply --resume "$ATTEMPT"
pwtest_re 'confirmed|noop' "resume reports the observed state"
grep -q -- '--method PUT' "$PWTEST_FORGE_LOG" && pwtest_bad "resume write" "resume repeated the forge write" || pwtest_ok "resume did not repeat the forge write"
AFTER="$(grep -c 'readiness draft confirmed' "$PW_PROJECTS_DIR/$P/LOG.md" || true)"
pwtest_eq "resume did not duplicate the log event" "$BEFORE" "$AFTER"

# --- GitHub uses native readiness, never the title prefix ---------------------
G=rdyg; rm -rf "$PW_PROJECTS_DIR/$G"; cp -a "$F2" "$PW_PROJECTS_DIR/$G"
sed -i '' 's|https://gitlab.example.com/pwtest/api/-/merge_requests/42|https://github.com/pwtest/api/pull/42|' "$PW_PROJECTS_DIR/$G/task/T02.md"
printf '42 ready\n' > "$PWTEST_GH_DRAFT_FILE"
printf '42 Draft: Ready despite the prefix\n' > "$PWTEST_GH_TITLE_FILE"
: > "$PWTEST_FORGE_STATE_FILE"; printf '42 open\n' >> "$PWTEST_FORGE_STATE_FILE"
pwtest_rc 0 "github preview draft" "$(pwtest_script $SH)" draft --project "$G" --task T02
pwtest_re 'T02\|.*\|ready\|draft\|change' "github reads native ready despite a Draft: title"
GT="$(sed -n 's/^token: //p' "$PWTEST_OUT")"
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "github demote" "$(pwtest_script $SH)" draft --project "$G" --task T02 --apply --expect "$GT"
pwtest_re 'confirmed' "github demote confirmed"
grep -q 'convertPullRequestToDraft' "$PWTEST_FORGE_LOG" && pwtest_ok "github demote used the native mutation" || pwtest_bad "github demote" "$(cat "$PWTEST_FORGE_LOG")"
grep -q '^42 draft$' "$PWTEST_GH_DRAFT_FILE" && pwtest_ok "github draft state recorded" || pwtest_bad "github state" "$(cat "$PWTEST_GH_DRAFT_FILE")"
grep -q '^42 Draft: Ready despite the prefix$' "$PWTEST_GH_TITLE_FILE" && pwtest_ok "github title left untouched" || pwtest_bad "github title" "title was rewritten"
pwtest_rc 0 "github preview ready" "$(pwtest_script $SH)" ready --project "$G" --task T02
GR="$(sed -n 's/^token: //p' "$PWTEST_OUT")"
pwtest_rc 0 "github promote" "$(pwtest_script $SH)" ready --project "$G" --task T02 --apply --expect "$GR"
grep -q 'markPullRequestReadyForReview' "$PWTEST_FORGE_LOG" && pwtest_ok "github promote used the native mutation" || pwtest_bad "github promote" "$(cat "$PWTEST_FORGE_LOG")"

# --- draft creation (GitLab + GitHub) -----------------------------------------
mkdir -p "$PW_PROJECTS_DIR/$P/worktree/api"
printf 'Ship readiness creation body\n' > "$ROOT/desc.md"
pwtest_rc 0 "draft creation (gitlab)" "$(pwtest_script $SH)" exec --project "$P" --task T01 --file "$ROOT/desc.md" --draft
tr '\n' ' ' < "$PWTEST_FORGE_LOG" | grep -q -- 'mr create .*--draft' && pwtest_ok "gitlab create received --draft" || pwtest_bad "gitlab draft flag" "$(cat "$PWTEST_FORGE_LOG")"
pwtest_re 'Readiness confirmed: draft' "creation readback confirms draft"
pwtest_rc 0 "normal creation (gitlab)" "$(pwtest_script $SH)" exec --project "$P" --task T04 --file "$ROOT/desc.md"
pwtest_re 'Readiness confirmed: ready' "normal creation readback confirms ready"

printf 'Ship readiness gh creation body\n' > "$ROOT/desc.md"
G2=rdyc; rm -rf "$PW_PROJECTS_DIR/$G2"; cp -a "$F2" "$PW_PROJECTS_DIR/$G2"
pwtest_repo ghapi "branch:agent/$G2/T01-thing"
git -C "$PW_REPOS/ghapi" remote set-url origin "https://github.com/pwtest/ghapi.git"
sed -i '' 's|^- \*\*Repo:\*\* api|- **Repo:** ghapi|' "$PW_PROJECTS_DIR/$G2/task/T01.md"
sed -i '' "s|agent/$S2/T01-thing|agent/$G2/T01-thing|; s|worktree/api/T01-thing|worktree/ghapi/T01-thing|" "$PW_PROJECTS_DIR/$G2/task/T01.md"
mkdir -p "$PW_PROJECTS_DIR/$G2/worktree/ghapi"
git -C "$PW_REPOS/ghapi" worktree add "$PW_PROJECTS_DIR/$G2/worktree/ghapi/T01-thing" "agent/$G2/T01-thing" >/dev/null 2>&1 || true
: > "$PWTEST_GH_DRAFT_FILE"; : > "$PWTEST_GH_TITLE_FILE"; : > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "draft creation (github)" env PWTEST_GH_CREATE_NUMBER=88 "$(pwtest_script $SH)" exec --project "$G2" --task T01 --file "$ROOT/desc.md" --draft
tr '\n' ' ' < "$PWTEST_FORGE_LOG" | grep -q -- 'pr create .*--draft' && pwtest_ok "github create received --draft" || pwtest_bad "github draft flag" "$(cat "$PWTEST_FORGE_LOG")"
pwtest_re 'Readiness confirmed: draft' "github creation readback confirms draft"

# --- unsupported draft capability refuses before push -------------------------
V=rdyv; rm -rf "$PW_PROJECTS_DIR/$V"; cp -a "$F2" "$PW_PROJECTS_DIR/$V"
pwtest_rc 2 "unsupported draft capability refuses" env PWTEST_GLAB_CREATE_NO_DRAFT=1 "$(pwtest_script $SH)" exec --project "$V" --task T01 --file "$ROOT/desc.md" --draft
pwtest_err 'cannot create a draft|nothing was pushed' "capability refusal is actionable"
grep -q 'Pushing' "$PWTEST_OUT" && pwtest_bad "capability order" "pushed before the draft capability check" || pwtest_ok "capability checked before push"
