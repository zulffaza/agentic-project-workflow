# shellcheck shell=bash
# cases/pw-rfc.t.sh — the rfc-doc entity (merged plan 20 Phase 4: comments + meta upserts).
R=rfc-f2; rm -rf "$PW_PROJECTS_DIR/$R"; cp -a "$F2" "$PW_PROJECTS_DIR/$R"
pwtest_rc 2 "no rfc dir → missing-setup error" "$(pwtest_script pw-rfc.sh)" comments "$R"
pwtest_fix "names a next command"
rm -rf "$PW_PROJECTS_DIR/$R"
mkdir -p "$PW_PROJECTS_DIR/${S2}rfc-copy" 2>/dev/null; true
pwtest_rc any "unknown backend rejected" env PW_RFC_BACKEND=nosuchbackend "$(pwtest_script pw-rfc.sh)" comments "$S2"
[ "$PWTEST_RC" != 0 ] ; pwtest_fix "backend refusal actionable"

# 4) rfc meta upserts + comment-seen
"$(pwtest_script pw-rfc.sh)" init "$RI" markdown >/dev/null 2>&1 || true
pwtest_rc 0 "rfc target" "$(pwtest_script pw-rfc.sh)" target "$RI" none-md-test
grep -q 'none-md-test' "$PW_PROJECTS_DIR/$RI/rfc/META.md" && pwtest_ok "rfc target persists" || pwtest_bad "rfc target" "$(cat "$PW_PROJECTS_DIR/$RI/rfc/META.md" 2>/dev/null | head -3 | tr '\n' ';')"
pwtest_rc 0 "rfc state wave1" "$(pwtest_script pw-rfc.sh)" state "$RI" Wave1Published yes
grep -qi 'wave 1 published' "$PW_PROJECTS_DIR/$RI/rfc/META.md" && pwtest_ok "rfc state persists (Wave 1 published)" || pwtest_bad "rfc state" "META unchanged: $(head -4 "$PW_PROJECTS_DIR/$RI/rfc/META.md")"
pwtest_rc 0 "rfc comment-seen (thread t99 solved=yes)" "$(pwtest_script pw-rfc.sh)" comment-seen "$RI" t99 2 yes
grep -qiE 't99' "$PW_PROJECTS_DIR/$RI/rfc/META.md" \
  && pwtest_ok "thread persisted in META" || pwtest_bad "rfc comment-seen" "$(tail -3 "$PW_PROJECTS_DIR/$RI/rfc/META.md" 2>/dev/null)"; 

# --- ported from pw-lib's inline selftest (plan 20 Phase 5) ---
pl_rfc_selftest() {
  local tmp="$ROOT/pl-rfc"; rm -rf "$tmp"; mkdir -p "$tmp/demo" "$tmp/demo2"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n' > "$tmp/demo/README.md"
  : > "$tmp/demo/LOG.md"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n' > "$tmp/demo2/README.md"
  : > "$tmp/demo2/LOG.md"
  die() { pwtest_bad "pw-lib-port[rfc]: $*" "ported selftest assert failed"; }
  # --- rfc side-loop -----------------------------------------------------
  # rfc init: creates rfc/RFC.md verbatim from the template (placeholder stamped), idempotent —
  # a 2nd call never clobbers a manual edit. Also ensures rfc/META.md, stamped with the REAL
  # backend passed in (not a hardcoded guess) — the bug a live fresh-context test caught.
  local RFC="$tmp/demo/rfc/RFC.md" META="$tmp/demo/rfc/META.md"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" init demo >/dev/null
  [ -f "$RFC" ] || die "selftest FAIL: rfc init did not create rfc/RFC.md"
  grep -q '^# RFC: demo$' "$RFC" || die "selftest FAIL: rfc init did not stamp the project slug"
  [ -f "$META" ] || die "selftest FAIL: rfc init did not also create rfc/META.md"
  grep -q '^- \*\*Backend:\*\* markdown$' "$META" || die "selftest FAIL: rfc init (no backend arg) did not default META.md's Backend to markdown"
  printf '\nmanual edit\n' >> "$RFC"                          # simulate a human/agent edit
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" init demo >/dev/null
  grep -q '^manual edit$' "$RFC" || die "selftest FAIL: rfc init clobbered an existing RFC.md"

  # rfc init <slug> <backend>: on a FRESH project (no rfc/ yet), stamps the REAL backend into
  # META.md from the start — this is the actual regression test for the bug above.
  mkdir -p "$tmp/backend-check"
  printf -- '- **Status:** context\n- **One-liner:** <x>\n' > "$tmp/backend-check/README.md"
  : > "$tmp/backend-check/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" init backend-check lark >/dev/null
  grep -q '^- \*\*Backend:\*\* lark$' "$tmp/backend-check/rfc/META.md" || die "selftest FAIL: rfc init <slug> lark did not stamp the real backend"

  # rfc target: upserts Target on the ALREADY-EXISTING META.md (from rfc init above), sets Target;
  # a 2nd call with a different ref replaces in place (still exactly one Target: line) without
  # touching Backend.
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" target demo "https://example.com/doc/1" >/dev/null
  grep -q '^- \*\*Target:\*\* https://example.com/doc/1$' "$META" || die "selftest FAIL: rfc target not set"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" target demo "https://example.com/doc/2" >/dev/null
  [ "$(grep -c '^- \*\*Target:\*\*' "$META")" = "1" ] || die "selftest FAIL: rfc target duplicated instead of replaced"
  grep -q '^- \*\*Target:\*\* https://example.com/doc/2$' "$META" || die "selftest FAIL: rfc target not updated"
  grep -q '^- \*\*Backend:\*\* markdown$' "$META" || die "selftest FAIL: rfc target touched an unrelated field"

  # rfc state: round-trips for each allowed field; an unknown field is rejected and leaves the
  # file untouched (same idiom as the backward-status-move guard above).
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" state demo Backend lark >/dev/null
  grep -q '^- \*\*Backend:\*\* lark$' "$META" || die "selftest FAIL: rfc state Backend not set"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" state demo Wave1Published yes >/dev/null
  grep -q '^- \*\*Wave 1 published:\*\* yes$' "$META" || die "selftest FAIL: rfc state Wave1Published not set"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" state demo Wave2Published yes >/dev/null
  grep -q '^- \*\*Wave 2 published:\*\* yes$' "$META" || die "selftest FAIL: rfc state Wave2Published not set"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" state demo LastRevision 42 >/dev/null
  grep -q '^- \*\*Last revision pushed:\*\* 42$' "$META" || die "selftest FAIL: rfc state LastRevision not set"
  if PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" state demo Bogus x >/dev/null 2>&1; then
    die "selftest FAIL: rfc state accepted an unknown field"
  fi
  if PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" state demo CommentCursor thread-9 >/dev/null 2>&1; then
    die "selftest FAIL: rfc state still accepts the retired CommentCursor field"
  fi
  grep -q '^- \*\*Last revision pushed:\*\* 42$' "$META" || die "selftest FAIL: rejected rfc state call mutated the file"

  # rfc comment-seen: per-thread tracking (replaces the old single-scalar Comment cursor, which
  # couldn't tell "an earlier thread got new replies" from "already handled" once a later thread
  # became the recorded 'latest'). New thread → new row; re-seeing the SAME thread with a higher
  # reply count updates that row in place (no duplicate); flipping solved does the same.
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" comment-seen demo thread-A 1 no >/dev/null
  grep -q '^## Comment tracking' "$META" || die "selftest FAIL: comment-seen did not create the tracking section"
  grep -qF '<!-- pw-rfc-comment:thread-A -->' "$META" || die "selftest FAIL: thread-A row not created"
  grep 'pw-rfc-comment:thread-A' "$META" | grep -q '| `thread-A` | 1 | no ' || die "selftest FAIL: thread-A row has wrong reply-count/solved"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" comment-seen demo thread-B 1 no >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: expected 2 tracked threads after thread-B"
  # thread-A gets a 2nd reply later (the exact scenario the scalar cursor got wrong) → same row,
  # updated in place, still only 2 tracked threads total (no duplicate for thread-A).
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" comment-seen demo thread-A 2 no >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: re-seeing thread-A duplicated a row instead of updating in place"
  grep 'pw-rfc-comment:thread-A' "$META" | grep -q '| `thread-A` | 2 | no ' || die "selftest FAIL: thread-A reply-count not updated"
  grep 'pw-rfc-comment:thread-B' "$META" | grep -q '| `thread-B` | 1 | no ' || die "selftest FAIL: thread-B wrongly changed by thread-A's update"
  # thread-B gets resolved externally → solved flips in place, still no duplicate.
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" comment-seen demo thread-B 1 yes >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: flipping solved duplicated thread-B's row"
  grep 'pw-rfc-comment:thread-B' "$META" | grep -q '| `thread-B` | 1 | yes ' || die "selftest FAIL: thread-B solved flag not updated"
  # validation: reply-count must be a non-negative integer, solved must be yes/no; a bad call is
  # rejected and doesn't touch existing rows.
  if PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" comment-seen demo thread-C -1 no >/dev/null 2>&1; then
    die "selftest FAIL: comment-seen accepted a negative reply-count"
  fi
  if PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" comment-seen demo thread-C 1 maybe >/dev/null 2>&1; then
    die "selftest FAIL: comment-seen accepted a non yes/no solved value"
  fi
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: rejected comment-seen calls still mutated the tracking table"

# (ship comment-seen asserts moved to scripts/entities/pw-ship.sh + tests/cases/pw-ship.t.sh — plan 20)

  # rfc dashboard: inserted after Adopted: when one exists (demo already has one from the adopt
  # tests above); inserted after One-liner when no Adopted: line exists (a fresh project); a 2nd
  # call replaces in place (still exactly one RFC: line either way).
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" dashboard demo "wave 1 published — https://example.com/doc/2" >/dev/null
  grep -q '^- \*\*RFC:\*\* wave 1 published' "$tmp/demo/README.md" || die "selftest FAIL: RFC line not inserted"
  grep -A1 '^- \*\*Adopted:\*\*' "$tmp/demo/README.md" | grep -q '^- \*\*RFC:\*\*' || die "selftest FAIL: RFC not anchored after Adopted:"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" dashboard demo "wave 2 published" >/dev/null
  [ "$(grep -c '^- \*\*RFC:\*\*' "$tmp/demo/README.md")" = "1" ] || die "selftest FAIL: RFC line duplicated instead of replaced"
  grep -q '^- \*\*RFC:\*\* wave 2 published$' "$tmp/demo/README.md" || die "selftest FAIL: RFC line not updated"

  mkdir -p "$tmp/demo2"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n' > "$tmp/demo2/README.md"
  : > "$tmp/demo2/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-rfc.sh)" dashboard demo2 "wave 1 published" >/dev/null
  grep -A1 '^- \*\*One-liner:\*\*' "$tmp/demo2/README.md" | grep -q '^- \*\*RFC:\*\*' || die "selftest FAIL: RFC not anchored after One-liner when no Adopted: exists"
  rm -rf "$tmp"
}
pl_rfc
