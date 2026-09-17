# shellcheck shell=bash
# cases/pw-doc-sync.t.sh — rebuild-on-clone: repair→lint-green, idempotent, Notes survive (C7).
S=sync-f2; rm -rf "$PW_PROJECTS_DIR/$S"; cp -a "$F2" "$PW_PROJECTS_DIR/$S"
D="$PW_PROJECTS_DIR/$S/README.md"
python3 - "$D" <<'PY'
import sys
f=sys.argv[1]; out=[]
for L in open(f):
    s=L.rstrip("\n")
    if s.startswith("| T01 |") and "| T01 |" in s:
        s=s.replace("| T01 |","| TXX |",1)       # renamed row → rebuild must drop it & re-add T01
    if s.startswith("| T02 |") and s.count("|")>=5:
        # hand-edit the Notes cell (last field) — the table rebuild must NEVER erase it (C7)
        parts=s.split("|"); parts[-2]=" handnote "
        s="|".join(parts)
    out.append(s+"\n")
open(f,"w").write("".join(out))
PY
pwtest_rc 1 "drifted dashboard lints red" "$(pwtest_script pw-doc-lint.sh)" dashboard "$S"
pwtest_fix "drift points at pw-doc-sync"
pwtest_rc 0 "sync --dashboard-only repairs" "$(pwtest_script pw-doc-sync.sh)" "$S" --dashboard-only
pwtest_rc 0 "post-repair lint green" "$(pwtest_script pw-doc-lint.sh)" dashboard "$S"
grep -q 'handnote' "$D" && pwtest_ok "C7 hand-written Notes preserved through rebuild" || pwtest_bad "C7 Notes preservation" "Notes wiped by rebuild (must never happen)"
grep -q '^| T02 | api' "$D" && pwtest_bad "C7 TXX stale row dropped" "renamed row survived rebuild" || pwtest_ok "C7 stale row dropped by rebuild"
cp "$D" "$ROOT/sync.pass1"
pwtest_rc 0 "sync second run" "$(pwtest_script pw-doc-sync.sh)" "$S" --dashboard-only
cmp -s "$ROOT/sync.pass1" "$D" && pwtest_ok "sync idempotent (second run no-op)" || pwtest_bad "sync idempotent" "README changed on a no-op run"
pwtest_rc 2 "sync unknown project rc2+fix" "$(pwtest_script pw-doc-sync.sh)" nope; pwtest_fix "sync unknown fix"
rm -rf "$PW_PROJECTS_DIR/$S"
