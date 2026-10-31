# shellcheck shell=bash
# cases/pw-gap-fixes.t.sh — the four defects a throwaway-project probe found (plan 55, E18):
#   G1  add-question --id seeds the blocking Q0 that the sequential allocator cannot produce
#   G2  resolve --withdraw closes an agent-seeded question that never reached the human
#   G3  pw-worktree.sh create adopts the task file's Branch:/Worktree: fields
#   G4  task lint rejects a done task whose Result lacks the machine bullets
# Each one previously needed a hand edit, which the bundle forbids.

GF="gapfix-probe"
GFDIR="$PW_PROJECTS_DIR/$GF"

# ---------------------------------------------------------------- G1 / G2
rm -rf "$GFDIR"; mkdir -p "$GFDIR/analysis" "$GFDIR/task" "$GFDIR/context"
cat > "$GFDIR/analysis/probe.md" <<'MD'
# Probe analysis

## 1. Goal

Change one default value.

## 2. Current state

Two call sites rely on it.

## 3. Scope

One repository.

## 4. Options

### 4.1 Option A

Edit in place.

### 4.2 Option B

Use a constant.

**Chosen approach:** _pending your review_

## 5. Decisions, risks, questions

### 5.1 Decisions log

- Nothing decided yet.
MD
printf '# Dashboard\n\n- **Status:** analysis\n' > "$GFDIR/README.md"
printf '# log\n' > "$GFDIR/LOG.md"
printf '# Context index\n' > "$GFDIR/context/INDEX.md"

pwtest_rc 0 "G1 review file created for the probe doc" \
  "$(pwtest_script pw-review.sh)" init --project "$GF" --file analysis/review/probe.review.md --doc analysis/probe.md

pwtest_rc 0 "G1 add-question --id Q0 succeeds" \
  "$(pwtest_script pw-review.sh)" add-question --project "$GF" --file analysis/review/probe.review.md \
  --id Q0 --section "§4 Approach" --text "which approach should we proceed with? (see §4)"
grep -qE '^### Q0 · §4 Approach' "$GFDIR/analysis/review/probe.review.md" \
  && pwtest_ok "G1 Q0 heading written in the exact shape pw-doc.sh lint reads" \
  || pwtest_bad "G1 Q0 heading" "$(grep -m3 '^### Q' "$GFDIR/analysis/review/probe.review.md" | tr '\n' '|')"

pwtest_rc 0 "G1 analysis lint accepts a pending approach with the seeded Q0" \
  "$(pwtest_script pw-doc.sh)" lint --kind analysis --project "$GF" --file probe --stage reviewable

pwtest_rc 2 "G1 a duplicate explicit id is refused" \
  "$(pwtest_script pw-review.sh)" add-question --project "$GF" --file analysis/review/probe.review.md \
  --id Q0 --section "§4 Approach" --text "second Q0 attempt"
pwtest_fix "duplicate Q0 refusal names the free-id path"

pwtest_rc 0 "G1 the next implicit id still allocates after Q0" \
  "$(pwtest_script pw-review.sh)" add-question --project "$GF" --file analysis/review/probe.review.md \
  --section "§5 Risk" --text "is the parked branch reusable?"
grep -qE '^### Q1 · §5 Risk' "$GFDIR/analysis/review/probe.review.md" \
  && pwtest_ok "G1 implicit allocation continues at Q1" \
  || pwtest_bad "G1 implicit allocation" "$(grep -m4 '^### Q' "$GFDIR/analysis/review/probe.review.md" | tr '\n' '|')"

pwtest_rc 0 "G2 an unanswered agent question can be withdrawn" \
  "$(pwtest_script pw-review.sh)" resolve --project "$GF" --file analysis/review/probe.review.md \
  --item Q1 --withdraw --reply "duplicate of Q0; nothing for the human to answer"

pwtest_rc 0 "G2 answering the blocking question is the normal path" \
  "$(pwtest_script pw-review.sh)" answer --project "$GF" --file analysis/review/probe.review.md \
  --question Q0 --text "Option A."

pwtest_rc 2 "G2 an answered question is never withdrawn" \
  "$(pwtest_script pw-review.sh)" resolve --project "$GF" --file analysis/review/probe.review.md \
  --item Q0 --withdraw --reply "trying to bury the human answer"
pwtest_fix "answered-question refusal tells the caller to fold instead"

pwtest_rc 2 "G2 a withdrawn question still needs its reply text" \
  "$(pwtest_script pw-review.sh)" resolve --project "$GF" --file analysis/review/probe.review.md --item Q1 --withdraw

# ---------------------------------------------------------------- G3
W3="gapfix-wt"; rm -rf "$PW_PROJECTS_DIR/$W3"; cp -a "$F2" "$PW_PROJECTS_DIR/$W3"
W3DIR="$PW_PROJECTS_DIR/$W3"
mkdir -p "$W3DIR/task"
cat > "$W3DIR/task/T01.md" <<'EOF'
# T01: descriptive slug probe

- **Repo:** api
- **Base branch:** master
- **Branch:** `agent/gapfix-wt/T01-descriptive-slug`
- **Worktree:** `worktree/api/T01-descriptive-slug/`
- **depends_on:** none
- **Stacked on:** none
- **Landing unit:** none
- **Status:** todo
- **Execute with:** pw-executor
- **Story points:** 1

## Goal
Probe only.

## Steps
1. Do nothing.
2. Do nothing else.
3. Stop.

## Verify
```bash
true
```

## Result (filled by the executor at run time)
EOF

pwtest_rc 0 "G3 task lint accepts a descriptor that branch and worktree share" \
  "$(pwtest_script pw-doc.sh)" lint --kind task --project "$W3" --file T01

pwtest_rc 0 "G3 create honors the task's descriptive Branch and Worktree" \
  "$(pwtest_script pw-worktree.sh)" create --project "$W3" --task T01 --repo api --base master
[ -d "$W3DIR/worktree/api/T01-descriptive-slug" ] \
  && pwtest_ok "G3 the worktree landed where the task file points" \
  || pwtest_bad "G3 worktree path" "$(ls "$W3DIR/worktree/api" 2>/dev/null | tr '\n' ' ')"
git -C "$PW_REPOS/api" worktree list | grep -q "T01-descriptive-slug" \
  && pwtest_ok "G3 the branch name came from the task file" \
  || pwtest_bad "G3 branch name" "$(git -C "$PW_REPOS/api" worktree list | tr '\n' '|')"

python3 - "$W3DIR/task/T01.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read().replace("worktree/api/T01-descriptive-slug/","worktree/api/T01-other-name/")
open(p,"w").write(s)
PY
pwtest_rc 1 "G3 task lint rejects branch and worktree descriptors that disagree" \
  "$(pwtest_script pw-doc.sh)" lint --kind task --project "$W3" --file T01
pwtest_fix "descriptor mismatch names both fields"

git -C "$PW_REPOS/api" worktree remove --force "$W3DIR/worktree/api/T01-descriptive-slug" >/dev/null 2>&1 || true
git -C "$PW_REPOS/api" branch -D "agent/gapfix-wt/T01-descriptive-slug" >/dev/null 2>&1 || true

# ---------------------------------------------------------------- G4
cat > "$W3DIR/task/T02.md" <<'EOF'
# T02: prose result

- **Repo:** api
- **Base branch:** master
- **Branch:** `agent/gapfix-wt/T02-prose`
- **Worktree:** `worktree/api/T02-prose/`
- **depends_on:** none
- **Stacked on:** none
- **Landing unit:** none
- **Status:** done
- **Execute with:** pw-executor
- **Story points:** 1

## Goal
Probe only.

## Steps
1. Do nothing.
2. Do nothing else.
3. Stop.

## Verify
```bash
true
```

## Result (filled by the executor at run time)
- **Outcome:** done
- **Commit(s):** `abc1234`

### Verify
A prose section that a human reads as complete.
EOF

pwtest_rc 1 "G4 task lint rejects a done task whose Result is not the machine shape" \
  "$(pwtest_script pw-doc.sh)" lint --kind task --project "$W3" --file T02

python3 - "$W3DIR/task/T02.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read().replace("### Verify\nA prose section that a human reads as complete.\n",
 "- **Verify outcome:** pass\n  - `PASS — true`\n")
open(p,"w").write(s)
PY
pwtest_rc 0 "G4 task lint accepts the template Result bullets" \
  "$(pwtest_script pw-doc.sh)" lint --kind task --project "$W3" --file T02

rm -rf "$PW_PROJECTS_DIR/$GF" "$W3DIR"
