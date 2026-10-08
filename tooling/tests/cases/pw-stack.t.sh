# shellcheck shell=bash
# cases/pw-stack.t.sh — stacked-MR lifecycle (plan 35): topology validation + resolver +
# effective target + state record + pending-operation recovery + worktree local inheritance +
# preflight debt gates. Focused cases build their OWN fixtures; shared $F2 is cloned, never
# mutated (fixture-pollution etiquette). Runs independently under --only stack.
SH=pw-ship.sh

# mkproj <slug> — minimal project dir the operators resolve (task/ + LOG.md; no scaffold needed).
stack_mkproj() {
  local s="$1"; rm -rf "$PW_PROJECTS_DIR/$s"
  mkdir -p "$PW_PROJECTS_DIR/$s/task"
  printf '# %s\n\n- **Status:** executing\n' "$s" > "$PW_PROJECTS_DIR/$s/README.md"
  : > "$PW_PROJECTS_DIR/$s/LOG.md"
  printf '%s' "$PW_PROJECTS_DIR/$s"
}
# stack_task <proj> <id> <repo> <base> <branch> <depends> <parent> <status>
stack_task() {
  local p="$1" id="$2" repo="$3" base="$4" br="$5" dep="$6" par="$7" st="$8"
  printf '%s\n' "# $id: stack fixture" \
    "- **Repo:** $repo" "- **Base branch:** $base" "- **Branch:** \`$br\`" \
    "- **Worktree:** \`worktree/$repo/$id-thing/\`" \
    "- **depends_on:** $dep" "- **Stacked on:** $par" "- **Status:** $st" \
    "- **MR:** —" > "$p/task/$id.md"
}
# _stack_branch_from <repo> <newbr> <basebr> — real branch <newbr> forked from <basebr> with one
# commit, pushed; leaves the repo on master. Used to build genuine A→B→C ancestry.
_stack_branch_from() {
  local repo="$1" nb="$2" bb="$3"
  git -C "$PW_REPOS/$repo" checkout -q "$bb"
  git -C "$PW_REPOS/$repo" checkout -q -b "$nb"
  printf 'c %s\n' "$nb" > "$PW_REPOS/$repo/c-$(printf '%s' "$nb" | tr '/' '-').txt"
  git -C "$PW_REPOS/$repo" add -A
  git -C "$PW_REPOS/$repo" -c user.email=t@t -c user.name=t commit -qm "c $nb"
  git -C "$PW_REPOS/$repo" push -q origin "$nb"
  git -C "$PW_REPOS/$repo" checkout -q master
}
# _st_get <projdir> <task> <col> — read one stack-state column via the shared library.
_st_get() { TOOL="$TOOL" bash -c '. "$TOOL/scripts/lib/pw-common.sh"; pw_stack_state_get "$1" "$2" "$3"' _ "$1" "$2" "$3"; }
# _stack_advance <repo> <branch> — one more commit on <branch>, pushed (simulates a landed fix).
_stack_advance() {
  local repo="$1" br="$2"
  git -C "$PW_REPOS/$repo" checkout -q "$br"
  printf 'x %s %s\n' "$br" "$(date +%s%N 2>/dev/null || date +%s)" > "$PW_REPOS/$repo/a-$(printf '%s' "$br" | tr '/' '-').txt"
  git -C "$PW_REPOS/$repo" add -A
  git -C "$PW_REPOS/$repo" -c user.email=t@t -c user.name=t commit -qm "advance $br"
  git -C "$PW_REPOS/$repo" push -q origin "$br"
  git -C "$PW_REPOS/$repo" checkout -q master
}

# --- topology + resolver (no git required) -----------------------------------
TP=stacktop; TP_DIR="$(stack_mkproj "$TP")"
stack_task "$TP_DIR" T01 api master agent/$TP/T01-thing none none done
stack_task "$TP_DIR" T02 api master agent/$TP/T02-thing T01 T01 done
stack_task "$TP_DIR" T03 api master agent/$TP/T03-thing T02 T02 todo
stack_task "$TP_DIR" T04 api master agent/$TP/T04-thing T02 T02 todo   # sibling child
pwtest_rc 0 "stack-validate: valid chain + sibling" "$(pwtest_script $SH)" stack-validate "$TP"
pwtest_re 'topology valid' "validate reports valid"
pwtest_rc 2 "stack-validate: missing project fails closed" "$(pwtest_script $SH)" stack-validate stack-nope-xyz
# zero writes on invalid topology: no state file is created just by validating
[ ! -f "$TP_DIR/task/stack.tsv" ] && pwtest_ok "read-only validate wrote no state" || pwtest_bad "validate purity" "stack.tsv created by a reader"

pwtest_rc 0 "stack: preview rows" "$(pwtest_script $SH)" stack "$TP"
pwtest_re "^T02\|T01\|agent/$TP/T01-thing\|" "T02 targets its parent branch"
pwtest_re "^T03\|T02\|agent/$TP/T02-thing\|" "T03 targets T02"
pwtest_re "^T01\|\|master\|" "T01 (root) targets master"

pwtest_rc 0 "stack-plan: root-first order" "$(pwtest_script $SH)" stack-plan "$TP"
# T01 must appear before T02, and T02 before T03/T04 in the ordered plan output.
_pl="$(cat "$PWTEST_OUT")"
printf '%s\n' "$_pl" | awk -F'|' '$1=="T01"{a=NR} $1=="T02"{b=NR} $1=="T03"{c=NR} END{exit !(a<b && b<c)}' \
  && pwtest_ok "plan orders ancestors before descendants" || pwtest_bad "plan order" "$_pl"

# descendants / ancestors primitives (via a tiny bash -c that sources pw-common)
pwtest_eq "descendants of T01 (BFS, parent-first)" \
  "$(PW_HOME="$PW_HOME" bash -c '. "'"$TOOL"'/scripts/lib/pw-common.sh"; pw_stack_descendants "'"$TP_DIR"'" T01' | tr '\n' ' ')" \
  "T02 T03 T04 "
pwtest_eq "ancestors of T03 (root-first)" \
  "$(PW_HOME="$PW_HOME" bash -c '. "'"$TOOL"'/scripts/lib/pw-common.sh"; pw_stack_ancestors "'"$TP_DIR"'" T03' | tr '\n' ' ')" \
  "T01 T02 "

# --- invalid topologies (each is its own project; validate must fail) --------
BAD=stackbad; BAD_DIR="$(stack_mkproj "$BAD")"
stack_task "$BAD_DIR" T01 api master agent/$BAD/T01-thing none T01 done      # self-parent
pwtest_rc 1 "stack-validate: self-parent rejected" "$(pwtest_script $SH)" stack-validate "$BAD"
stack_task "$BAD_DIR" T01 api master agent/$BAD/T01-thing none none done
stack_task "$BAD_DIR" T02 api master agent/$BAD/T02-thing T01 T99 done       # unknown parent
pwtest_rc 1 "stack-validate: unknown parent rejected" "$(pwtest_script $SH)" stack-validate "$BAD"
stack_task "$BAD_DIR" T02 api master agent/$BAD/T02-thing T01 T01 done
stack_task "$BAD_DIR" T03 api master agent/$BAD/T03-thing T02 T02 done
stack_task "$BAD_DIR" T01 api spring3 agent/$BAD/T01-thing none none done     # base mismatch
pwtest_rc 1 "stack-validate: incompatible destinations rejected" "$(pwtest_script $SH)" stack-validate "$BAD"
stack_task "$BAD_DIR" T01 api master agent/$BAD/T01-thing none none done
stack_task "$BAD_DIR" T02 other master agent/$BAD/T02-thing T01 T01 done     # cross-repo
pwtest_rc 1 "stack-validate: cross-repo parent rejected" "$(pwtest_script $SH)" stack-validate "$BAD"
stack_task "$BAD_DIR" T02 api master agent/$BAD/T02-thing none T01 done      # parent not in depends_on
pwtest_rc 1 "stack-validate: parent missing from depends_on rejected" "$(pwtest_script $SH)" stack-validate "$BAD"
# cycle: T01 -> T02 -> T01
stack_task "$BAD_DIR" T01 api master agent/$BAD/T01-thing T02 T02 done
stack_task "$BAD_DIR" T02 api master agent/$BAD/T02-thing T01 T01 done
pwtest_rc 1 "stack-validate: cycle rejected" "$(pwtest_script $SH)" stack-validate "$BAD"

# legacy: no stacks anywhere
pwtest_rc 0 "stack: legacy no-stacks on F1" "$(pwtest_script $SH)" stack "$S1"
pwtest_re 'no stacks' "legacy independent behavior reported"
rm -rf "$PW_PROJECTS_DIR/$TP" "$PW_PROJECTS_DIR/$BAD"

# --- verified landing + promotion + retarget (real Git) ----------------------
GD=stackgit; GD_DIR="$(stack_mkproj "$GD")"
# Dashboard with the real Merge-requests table shape (retarget mirrors Target branch there and must
# fail loudly if that mirror truly cannot be written; the blank placeholder row exercises the KI-2
# fill rule exactly like a fresh scaffold).
{ printf '# %s\n\n- **Status:** executing\n\n' "$GD"
  printf '## Merge requests\n\n| Task | Repo | MR | Target branch | State | Build |\n|------|------|----|--------------|-------|-------|\n| | | | | open / on-hold / merged | — |\n'
} > "$GD_DIR/README.md"
pwtest_repo gitrepo
_stack_branch_from gitrepo "agent/$GD/T01-$GD" master
_stack_branch_from gitrepo "agent/$GD/T02-$GD" "agent/$GD/T01-$GD"
_stack_branch_from gitrepo "agent/$GD/T03-$GD" "agent/$GD/T02-$GD"
_stack_branch_from gitrepo "agent/$GD/T04-$GD" master
stack_task "$GD_DIR" T01 gitrepo master "agent/$GD/T01-$GD" none none done
stack_task "$GD_DIR" T02 gitrepo master "agent/$GD/T02-$GD" T01 T01 done
stack_task "$GD_DIR" T03 gitrepo master "agent/$GD/T03-$GD" T02 T02 todo
stack_task "$GD_DIR" T04 gitrepo master "agent/$GD/T04-$GD" T01 T01 todo
printf 'T01 verify\n' > "$ROOT/ev-T01"; printf 'T02 verify\n' > "$ROOT/ev-T02"; printf 'T03 verify\n' > "$ROOT/ev-T03"; printf 'T04 verify\n' > "$ROOT/ev-T04"

pwtest_rc 0 "stack-verify root T01" "$(pwtest_script $SH)" stack-verify "$GD" T01 "$ROOT/ev-T01"
pwtest_rc 2 "stack-verify refuses a child without the parent commit" "$(pwtest_script $SH)" stack-verify "$GD" T04 "$ROOT/ev-T04"
pwtest_err 'does not contain parent' "ancestry refusal names the missing parent commit"
pwtest_rc 0 "stack-verify child T02 (parent ancestry proven from Git)" "$(pwtest_script $SH)" stack-verify "$GD" T02 "$ROOT/ev-T02"
pwtest_rc 0 "stack-verify grandchild T03" "$(pwtest_script $SH)" stack-verify "$GD" T03 "$ROOT/ev-T03"
pwtest_eq "T02 verified_target = parent branch" "$(_st_get "$GD_DIR" T02 verified_target)" "agent/$GD/T01-$GD"
pwtest_eq "T03 verified_target = parent branch" "$(_st_get "$GD_DIR" T03 verified_target)" "agent/$GD/T02-$GD"
pwtest_rc 0 "stack reads fresh after real verify" "$(pwtest_script $SH)" stack "$GD"
pwtest_re '^T02\|T01\|agent/'"$GD"'/T01-'"$GD"'\|.*\|fresh\|' "T02 fresh after a real verification tuple"

pwtest_rc 0 "promote T03 before any landing = noop" "$(pwtest_script $SH)" stack-promote "$GD" T03
pwtest_re '^noop\|agent/'"$GD"'/T02-'"$GD"'$' "no promotion before a landing"

# unproven landing refused: T01's verified commit is NOT in master yet
pwtest_rc 2 "stack-land refuses an unproven merge" "$(pwtest_script $SH)" stack-land "$GD" T01 "$(git -C "$PW_REPOS/gitrepo" rev-parse master)" master merge
pwtest_err 'NOT an ancestor' "refusal names the missing destination ancestry"

# real merge of T01 into master, then the landing IS provable
git -C "$PW_REPOS/gitrepo" checkout -q master
git -C "$PW_REPOS/gitrepo" merge -q --no-ff "agent/$GD/T01-$GD" -m "merge T01"
git -C "$PW_REPOS/gitrepo" push -q origin master
MSHA="$(git -C "$PW_REPOS/gitrepo" rev-parse master)"
pwtest_rc 0 "stack-land T01 merge (Git-proven)" "$(pwtest_script $SH)" stack-land "$GD" T01 "$MSHA" master merge
pwtest_rc 0 "promote T02 after T01 lands" "$(pwtest_script $SH)" stack-promote "$GD" T02
pwtest_re '^promote\|master$' "T02 promotes to the ultimate base after its parent lands"
pwtest_rc 0 "promote T03 while T02 open" "$(pwtest_script $SH)" stack-promote "$GD" T03
pwtest_re '^noop\|agent/'"$GD"'/T02-'"$GD"'$' "T03 unchanged while T02 still open"

# retarget T02's MR to master via the forge shim: stateful write + readback + recovery row
git -C "$PW_REPOS/gitrepo" worktree add "$GD_DIR/worktree/gitrepo/T02-$GD" "agent/$GD/T02-$GD" >/dev/null 2>&1 || true
printf '\n## Result\n- **MR:** https://gitlab.example.com/pwtest/gitrepo/-/merge_requests/55\n' >> "$GD_DIR/task/T02.md"
printf '55 agent/%s/T01-%s\n' "$GD" "$GD" > "$PWTEST_ROOT/gd-targets"
export PWTEST_MR_TARGETS_FILE="$PWTEST_ROOT/gd-targets"
pwtest_rc 0 "retarget dry-run previews" "$(pwtest_script $SH)" stack-retarget "$GD" T02
pwtest_re '^retarget-preview\|master' "dry-run previews the new target"
grep -q '^55 agent/'"$GD"'/T01-'"$GD"'$' "$PWTEST_ROOT/gd-targets" \
  && pwtest_ok "dry-run left the MR target unchanged" || pwtest_bad "retarget dry-run purity" "target rewritten during preview"
pwtest_rc 0 "retarget --apply publishes to the forge" "$(pwtest_script $SH)" stack-retarget "$GD" T02 --apply
pwtest_re '^promote\|master' "apply reports the promoted target"
grep -q '^55 master$' "$PWTEST_ROOT/gd-targets" \
  && pwtest_ok "forge shim observed the new target (stateful write)" || pwtest_bad "retarget apply write" "$(cat "$PWTEST_ROOT/gd-targets")"
pwtest_eq "state target updated after observed retarget" "$(_st_get "$GD_DIR" T02 target)" "master"
pwtest_eq "retarget recovery op marked done" \
  "$(awk -F'\t' '$1=="retarget:T02"{print $8}' "$GD_DIR/task/stack-ops.tsv")" "done"
unset PWTEST_MR_TARGETS_FILE

pwtest_rc 2 "stack-record refuses landed=yes (no guessed authority)" "$(pwtest_script $SH)" stack-record "$GD" T03 landed=yes
rm -rf "$PW_PROJECTS_DIR/$GD"

# --- squash / closed / unknown landing verdicts (forge corroboration) --------
SQ=stacksq; SQ_DIR="$(stack_mkproj "$SQ")"
pwtest_repo sqrepo
_stack_branch_from sqrepo "agent/$SQ/T01-$SQ" master
_stack_branch_from sqrepo "agent/$SQ/T02-$SQ" "agent/$SQ/T01-$SQ"
stack_task "$SQ_DIR" T01 sqrepo master "agent/$SQ/T01-$SQ" none none done
stack_task "$SQ_DIR" T02 sqrepo master "agent/$SQ/T02-$SQ" T01 T01 done
printf 'sq1\n' > "$ROOT/ev-sq-1"; printf 'sq2\n' > "$ROOT/ev-sq-2"
pwtest_rc 0 "sq stack-verify T01" "$(pwtest_script $SH)" stack-verify "$SQ" T01 "$ROOT/ev-sq-1"
pwtest_rc 0 "sq stack-verify T02" "$(pwtest_script $SH)" stack-verify "$SQ" T02 "$ROOT/ev-sq-2"
git -C "$PW_REPOS/sqrepo" worktree add "$SQ_DIR/worktree/sqrepo/T01-$SQ" "agent/$SQ/T01-$SQ" >/dev/null 2>&1 || true
printf '\n## Result\n- **MR:** https://gitlab.example.com/pwtest/sqrepo/-/merge_requests/77\n' >> "$SQ_DIR/task/T01.md"
printf '77 merged\n' > "$PWTEST_FORGE_STATE_FILE"
pwtest_rc 0 "stack-land squash (forge merged + destination exists)" "$(pwtest_script $SH)" stack-land "$SQ" T01 - master squash
pwtest_rc 1 "promote blocks on a squashed parent" "$(pwtest_script $SH)" stack-promote "$SQ" T02
pwtest_re '^block\|.*squash' "squash block names the reason"
printf '77 closed\n' > "$PWTEST_FORGE_STATE_FILE"
pwtest_rc 0 "stack-land closed (forge closed)" "$(pwtest_script $SH)" stack-land "$SQ" T01 - master closed
pwtest_rc 1 "promote blocks on a closed parent" "$(pwtest_script $SH)" stack-promote "$SQ" T02
pwtest_re '^block\|.*closed' "closed block names the reason"
printf '77 opened\n' > "$PWTEST_FORGE_STATE_FILE"
pwtest_rc 2 "stack-land unknown refused (no unprovable record)" "$(pwtest_script $SH)" stack-land "$SQ" T01 - master unknown
rm -rf "$PW_PROJECTS_DIR/$SQ"

# --- transitive freshness + upstream propagation (real Git) ------------------
CS=stackcs; CS_DIR="$(stack_mkproj "$CS")"
pwtest_repo csrepo
_stack_branch_from csrepo "agent/$CS/T01-$CS" master
_stack_branch_from csrepo "agent/$CS/T02-$CS" "agent/$CS/T01-$CS"
_stack_branch_from csrepo "agent/$CS/T03-$CS" "agent/$CS/T02-$CS"
stack_task "$CS_DIR" T01 csrepo master "agent/$CS/T01-$CS" none none done
stack_task "$CS_DIR" T02 csrepo master "agent/$CS/T02-$CS" T01 T01 done
stack_task "$CS_DIR" T03 csrepo master "agent/$CS/T03-$CS" T02 T02 done
printf 'cs1\n' > "$ROOT/ev-cs-1"; printf 'cs2\n' > "$ROOT/ev-cs-2"; printf 'cs3\n' > "$ROOT/ev-cs-3"
pwtest_rc 0 "cs verify T01" "$(pwtest_script $SH)" stack-verify "$CS" T01 "$ROOT/ev-cs-1"
pwtest_rc 0 "cs verify T02" "$(pwtest_script $SH)" stack-verify "$CS" T02 "$ROOT/ev-cs-2"
pwtest_rc 0 "cs verify T03" "$(pwtest_script $SH)" stack-verify "$CS" T03 "$ROOT/ev-cs-3"
pwtest_rc 0 "cs chain fresh" "$(pwtest_script $SH)" stack "$CS"
pwtest_re '^T03\|T02\|agent/'"$CS"'/T02-'"$CS"'\|.*\|fresh\|' "grandchild fresh after verify"
# an upstream fix on T01 (no comments involved) must invalidate the whole subtree
_stack_advance csrepo "agent/$CS/T01-$CS"
printf 'cs1b\n' > "$ROOT/ev-cs-1b"
pwtest_rc 0 "cs re-verify T01 after the upstream fix" "$(pwtest_script $SH)" stack-verify "$CS" T01 "$ROOT/ev-cs-1b"
pwtest_rc 0 "cs stack after the upstream fix" "$(pwtest_script $SH)" stack "$CS"
pwtest_re '^T02\|.*\|stale\|' "child stale when the parent head moves"
pwtest_re '^T03\|.*\|stale\|' "grandchild stale transitively (old green refused)"
pwtest_rc any "cs stack-plan after the fix" "$(pwtest_script $SH)" stack-plan "$CS" T03
pwtest_re '^T03\|.*\|no\|.*stale' "stale grandchild is not ready to publish"
# integrate the fix down the chain and re-verify each step
git -C "$PW_REPOS/csrepo" checkout -q "agent/$CS/T02-$CS"
git -C "$PW_REPOS/csrepo" merge -q --no-edit "agent/$CS/T01-$CS"
git -C "$PW_REPOS/csrepo" push -q origin "agent/$CS/T02-$CS"
git -C "$PW_REPOS/csrepo" checkout -q master
printf 'cs2b\n' > "$ROOT/ev-cs-2b"
pwtest_rc 0 "cs re-verify T02 after integration" "$(pwtest_script $SH)" stack-verify "$CS" T02 "$ROOT/ev-cs-2b"
git -C "$PW_REPOS/csrepo" checkout -q "agent/$CS/T03-$CS"
git -C "$PW_REPOS/csrepo" merge -q --no-edit "agent/$CS/T02-$CS"
git -C "$PW_REPOS/csrepo" push -q origin "agent/$CS/T03-$CS"
git -C "$PW_REPOS/csrepo" checkout -q master
printf 'cs3b\n' > "$ROOT/ev-cs-3b"
pwtest_rc 0 "cs re-verify T03 after integration" "$(pwtest_script $SH)" stack-verify "$CS" T03 "$ROOT/ev-cs-3b"
pwtest_rc 0 "cs chain fresh again" "$(pwtest_script $SH)" stack "$CS"
pwtest_re '^T03\|T02\|agent/'"$CS"'/T02-'"$CS"'\|.*\|fresh\|' "grandchild fresh after propagation completes"
rm -rf "$PW_PROJECTS_DIR/$CS"

# --- pending operation recovery + debt ---------------------------------------
OP=stackop; OP_DIR="$(stack_mkproj "$OP")"
stack_task "$OP_DIR" T01 api master agent/$OP/T01-thing none none done
stack_task "$OP_DIR" T02 api master agent/$OP/T02-thing T01 T01 done
pwtest_rc 0 "op create (pending)" "$(pwtest_script $SH)" stack-op "$OP" create cascade:T01 cascade T01 sha1 "integrate=pending;verify=pending;push=pending"
pwtest_rc 1 "stack-debt blocks while pending" "$(pwtest_script $SH)" stack-debt "$OP"
pwtest_err 'pending stack operation' "debt names the blocker"
pwtest_rc 0 "op set stages" "$(pwtest_script $SH)" stack-op "$OP" set cascade:T01 "integrate=done;verify=done;push=done"
pwtest_rc 0 "stack-debt clear once done" "$(pwtest_script $SH)" stack-debt "$OP"
pwtest_eq "op state derived done" \
  "$(awk -F'\t' 'NR>1{print $8}' "$OP_DIR/task/stack-ops.tsv")" "done"
pwtest_rc 0 "op list" "$(pwtest_script $SH)" stack-op "$OP" list
pwtest_re 'cascade:T01' "listed op"
pwtest_rc 0 "op clear" "$(pwtest_script $SH)" stack-op "$OP" clear cascade:T01
[ "$(awk -F'\t' 'NR>1{print}' "$OP_DIR/task/stack-ops.tsv" | grep -c . || true)" = "0" ] && pwtest_ok "op cleared" || pwtest_bad "op clear" "row stayed"
rm -rf "$PW_PROJECTS_DIR/$OP"

# --- worktree local verified-parent inheritance (real disposable Git) ---------
WT=stackwt; WT_DIR="$(stack_mkproj "$WT")"
# branch names follow the worktree convention agent/<slug>/<T0n>-<slug> (the child's own identity)
pwtest_repo stackrepo "branch:agent/$WT/T01-$WT"
PHEAD="$(git -C "$PW_REPOS/stackrepo" rev-parse "agent/$WT/T01-$WT")"
stack_task "$WT_DIR" T01 stackrepo master "agent/$WT/T01-$WT" none none done
stack_task "$WT_DIR" T02 stackrepo master "agent/$WT/T02-$WT" T01 T01 todo
# (a) missing verified binding must refuse: no silent fork from a stale ref
pwtest_rc 2 "worktree: stacked child refuses without a verified parent binding" "$(pwtest_script pw-worktree.sh)" create "$WT" T02 stackrepo master
pwtest_err 'no verified commit binding' "refusal names the missing binding"
# (b) bind the parent's verified head via stack-verify, then fork from the EXACT local commit
printf 'wt T01 verify\n' > "$ROOT/ev-wt-T01"
pwtest_rc 0 "stack-verify T01 (binds its verified head)" "$(pwtest_script $SH)" stack-verify "$WT" T01 "$ROOT/ev-wt-T01"
pwtest_rc 0 "worktree: create stacked child from parent's verified commit" "$(pwtest_script pw-worktree.sh)" create "$WT" T02 stackrepo master
CW="$WT_DIR/worktree/stackrepo/T02-$WT"
[ -d "$CW" ] && pwtest_ok "child worktree mounted" || pwtest_bad "child worktree" "not mounted"
CHEAD="$(git -C "$PW_REPOS/stackrepo" rev-parse "agent/$WT/T02-$WT" 2>/dev/null || true)"
pwtest_eq "child branch HEAD == parent verified SHA (exact local fork)" "$PHEAD" "$CHEAD"
pwtest_eq "fork binding recorded" "$(awk -F'\t' '$1=="T02"{print $5}' "$WT_DIR/task/stack.tsv")" "$PHEAD"
# (c) parent head changed after verification → stale evidence refused
git -C "$PW_REPOS/stackrepo" checkout -q "agent/$WT/T01-$WT"
printf 'drift\n' > "$PW_REPOS/stackrepo/drift.txt"; git -C "$PW_REPOS/stackrepo" add -A
git -C "$PW_REPOS/stackrepo" -c user.email=t@t -c user.name=t commit -qm drift
git -C "$PW_REPOS/stackrepo" checkout -q master
stack_task "$WT_DIR" T03 stackrepo master "agent/$WT/T03-$WT" T01 T01 todo
pwtest_rc 2 "worktree: changed parent head rejected (stale evidence)" "$(pwtest_script pw-worktree.sh)" create "$WT" T03 stackrepo master
pwtest_err 'head changed after verification' "stale-head refusal names the cause"
rm -rf "$PW_PROJECTS_DIR/$WT"

# --- adoption: infer an edge from the real (shim) MR target ------------------
AD=stackadopt; AD_DIR="$(stack_mkproj "$AD")"
pwtest_repo adoptrepo "branch:agent/$AD/T01-$AD" "branch:agent/$AD/T02-$AD"
git -C "$PW_REPOS/adoptrepo" worktree add "$AD_DIR/worktree/adoptrepo/T02-$AD" "agent/$AD/T02-$AD" >/dev/null 2>&1 || true
stack_task "$AD_DIR" T01 adoptrepo master "agent/$AD/T01-$AD" none none done
stack_task "$AD_DIR" T02 adoptrepo master "agent/$AD/T02-$AD" T01 none done
printf '\n## Result\n- **MR:** https://gitlab.example.com/pwtest/adoptrepo/-/merge_requests/55\n' >> "$AD_DIR/task/T02.md"
printf '55 agent/%s/T01-%s\n' "$AD" "$AD" > "$PWTEST_ROOT/adopt-targets"
export PWTEST_MR_TARGETS_FILE="$PWTEST_ROOT/adopt-targets"
# dry-run: preview only, no writes
pwtest_rc 0 "stack-adopt dry-run infers the edge" "$(pwtest_script $SH)" stack-adopt "$AD"
pwtest_re "T02 <- T01" "adopt preview shows the inferred parent"
pwtest_re 'preview only' "adopt announces preview"
grep -q 'Stacked on: T01' "$AD_DIR/task/T02.md" && pwtest_bad "adopt dry-run purity" "field written during preview" || pwtest_ok "adopt preview wrote nothing"
# apply: import the proven edge
pwtest_rc 0 "stack-adopt --apply imports" "$(pwtest_script $SH)" stack-adopt "$AD" --apply
grep -q '^- \*\*Stacked on:\*\* T01$' "$AD_DIR/task/T02.md" && pwtest_ok "adopt wrote the Stacked on field" || pwtest_bad "adopt apply" "$(grep 'Stacked on' "$AD_DIR/task/T02.md")"
unset PWTEST_MR_TARGETS_FILE
rm -rf "$PW_PROJECTS_DIR/$AD"

# --- ship exec: the child's MR targets the effective parent branch -----------
EX=stackexec; EX_DIR="$(stack_mkproj "$EX")"
pwtest_repo execrepo
_stack_branch_from execrepo "agent/$EX/T01-$EX" master
_stack_branch_from execrepo "agent/$EX/T02-$EX" "agent/$EX/T01-$EX"
printf 'stacked child MR\n' > "$ROOT/desc-stack.md"
: > "$EX_DIR/task/PLAN.md"   # exec requires the PLAN file to exist
stack_task "$EX_DIR" T01 execrepo master "agent/$EX/T01-$EX" none none done
stack_task "$EX_DIR" T02 execrepo master "agent/$EX/T02-$EX" T01 T01 done
printf 'ex1\n' > "$ROOT/ev-ex-1"; printf 'ex2\n' > "$ROOT/ev-ex-2"
pwtest_rc 0 "exec pre-req: verify T01" "$(pwtest_script $SH)" stack-verify "$EX" T01 "$ROOT/ev-ex-1"
pwtest_rc 0 "exec pre-req: verify T02" "$(pwtest_script $SH)" stack-verify "$EX" T02 "$ROOT/ev-ex-2"
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "ship exec: stacked child creates its MR" "$(pwtest_script $SH)" exec "$EX" T02 "$ROOT/desc-stack.md"
grep -q "target-branch agent/$EX/T01-$EX" "$PWTEST_FORGE_LOG" \
  && pwtest_ok "MR create targeted the effective parent branch" \
  || pwtest_bad "effective target in exec" "$(tr '\n' ';' < "$PWTEST_FORGE_LOG")"
grep -q '^- \*\*MR:\*\* https' "$EX_DIR/task/T02.md" && pwtest_ok "MR URL recorded on the child" || pwtest_bad "child MR record" "no URL"
# entity-boundary gate: a stale child is refused even without the preflight
_stack_advance execrepo "agent/$EX/T02-$EX"
pwtest_rc 2 "exec denies a stale stacked child at the entity boundary" "$(pwtest_script $SH)" exec "$EX" T02 "$ROOT/desc-stack.md"
pwtest_err 'stale' "exec refusal names the stale verification tuple"
rm -rf "$PW_PROJECTS_DIR/$EX"

# --- doctor: field ↔ PLAN mirror disagreement is reported --------------------
DOC=stackdoc; DOC_DIR="$(stack_mkproj "$DOC")"
stack_task "$DOC_DIR" T01 api master "agent/$DOC/T01-$DOC" none none done
stack_task "$DOC_DIR" T02 api master "agent/$DOC/T02-$DOC" T01 T01 done
printf '%s\n' '## Task table' \
  '| ID | Title | Repo | depends_on | Stacked on | Group | Execute with | SP | Status | Time | Result |' \
  '|----|-------|------|-----------|------------|-------|--------------|----|--------|------|--------|' \
  '| T01 | a | api | — | — | G1 | claude:opus | 1 | done | — | — |' \
  '| T02 | b | api | T01 | — | G1 | claude:opus | 1 | done | — | — |' > "$DOC_DIR/task/PLAN.md"
pwtest_rc any "doctor reports the Stacked on mirror mismatch" "$(pwtest_script pw-project-doctor.sh)" "$DOC"
pwtest_re 'mirror disagrees' "doctor names the PLAN mirror disagreement"
rm -rf "$PW_PROJECTS_DIR/$DOC"

# --- fail-closed target + no false promote (M1/M4) --------------------------
M1=stackm1; M1_DIR="$(stack_mkproj "$M1")"
printf '%s\n' "# T01" "- **Repo:** api" "- **Base branch:** master" "- **Branch:**" \
  "- **depends_on:** none" "- **Stacked on:** none" "- **Status:** done" > "$M1_DIR/task/T01.md"
stack_task "$M1_DIR" T02 api master "agent/$M1/T02-$M1" T01 T01 done
pwtest_rc 0 "M1 stack preview runs" "$(pwtest_script $SH)" stack "$M1"
pwtest_re '^T02\|T01\|BLOCKED\|' "an open ancestor with no Branch fails closed (never defaults to master)"
pwtest_rc 0 "M1 stack-plan runs" "$(pwtest_script $SH)" stack-plan "$M1" T02
pwtest_re '^T02\|.*\|BLOCKED\|.*\|no\|' "the unresolvable target is not ready to publish"
rm -rf "$PW_PROJECTS_DIR/$M1"

M4=stackm4; M4_DIR="$(stack_mkproj "$M4")"
pwtest_repo m4repo
_stack_branch_from m4repo "agent/$M4/T01-$M4" master
_stack_branch_from m4repo "agent/$M4/T02-$M4" "agent/$M4/T01-$M4"
stack_task "$M4_DIR" T01 m4repo master "agent/$M4/T01-$M4" none none done
stack_task "$M4_DIR" T02 m4repo master "agent/$M4/T02-$M4" T01 T01 done
printf 'm4\n' > "$ROOT/ev-m4-1"
pwtest_rc 0 "M4 verify T01" "$(pwtest_script $SH)" stack-verify "$M4" T01 "$ROOT/ev-m4-1"
git -C "$PW_REPOS/m4repo" checkout -q master
git -C "$PW_REPOS/m4repo" merge -q --no-ff "agent/$M4/T01-$M4" -m "merge T01"
git -C "$PW_REPOS/m4repo" push -q origin master
pwtest_rc 0 "M4 land T01 (merge)" "$(pwtest_script $SH)" stack-land "$M4" T01 master master merge
pwtest_rc 1 "M4 promote blocks on a missing child record" "$(pwtest_script $SH)" stack-promote "$M4" T02
pwtest_re '^block\|.*no recorded target' "a missing record blocks instead of a false promote"
rm -rf "$PW_PROJECTS_DIR/$M4"

# --- destination open ancestor preserved (merge into another open ancestor) --
EO=stackeo; EO_DIR="$(stack_mkproj "$EO")"
pwtest_repo eorepo
_stack_branch_from eorepo "agent/$EO/T01-$EO" master
_stack_branch_from eorepo "agent/$EO/T02-$EO" "agent/$EO/T01-$EO"
_stack_branch_from eorepo "agent/$EO/T03-$EO" "agent/$EO/T02-$EO"
stack_task "$EO_DIR" T01 eorepo master "agent/$EO/T01-$EO" none none done
stack_task "$EO_DIR" T02 eorepo master "agent/$EO/T02-$EO" T01 T01 done
stack_task "$EO_DIR" T03 eorepo master "agent/$EO/T03-$EO" T02 T02 done
printf 'eo1\n' > "$ROOT/ev-eo-1"; printf 'eo2\n' > "$ROOT/ev-eo-2"; printf 'eo3\n' > "$ROOT/ev-eo-3"
pwtest_rc 0 "EO verify T01" "$(pwtest_script $SH)" stack-verify "$EO" T01 "$ROOT/ev-eo-1"
pwtest_rc 0 "EO verify T02" "$(pwtest_script $SH)" stack-verify "$EO" T02 "$ROOT/ev-eo-2"
pwtest_rc 0 "EO verify T03" "$(pwtest_script $SH)" stack-verify "$EO" T03 "$ROOT/ev-eo-3"
# T02 lands INTO T01's still-open branch (not the ultimate base)
git -C "$PW_REPOS/eorepo" checkout -q "agent/$EO/T01-$EO"
git -C "$PW_REPOS/eorepo" merge -q --no-ff "agent/$EO/T02-$EO" -m "merge T02 into T01"
git -C "$PW_REPOS/eorepo" push -q origin "agent/$EO/T01-$EO"
git -C "$PW_REPOS/eorepo" checkout -q master
pwtest_rc 0 "EO stack-land T02 into T01's open branch" "$(pwtest_script $SH)" stack-land "$EO" T02 "$(git -C "$PW_REPOS/eorepo" rev-parse "agent/$EO/T01-$EO")" "agent/$EO/T01-$EO" merge
pwtest_rc 0 "EO promote T03 targets the open ancestor" "$(pwtest_script $SH)" stack-promote "$EO" T03
pwtest_re '^promote\|agent/'"$EO"'/T01-'"$EO"'$' "destination open ancestor preserved, not the ultimate base"
rm -rf "$PW_PROJECTS_DIR/$EO"

# --- writer hardening + arity guards ------------------------------------------
WH=stackwh; WH_DIR="$(stack_mkproj "$WH")"
stack_task "$WH_DIR" T01 api master "agent/$WH/T01-$WH" none none done
stack_task "$WH_DIR" T02 api master "agent/$WH/T02-$WH" T01 T01 done
pwtest_rc 2 "stack-record refuses a reserved pipe in a value" "$(pwtest_script $SH)" stack-record "$WH" T02 "branch=a|b"
pwtest_err 'reserved character' "reserved-char refusal names the cause"
pwtest_rc 2 "stack-op create refuses a reserved pipe in stages" "$(pwtest_script $SH)" stack-op "$WH" create k1 cascade T01 ev "a=pending|x"
pwtest_rc 2 "stack-fresh arity guard" "$(pwtest_script $SH)" stack-fresh "$WH"
pwtest_err 'usage: stack-fresh' "missing task id is a usage error, not an unbound-variable crash"
mkdir -p "$PWTEST_ROOT/outside"
: > "$PWTEST_ROOT/outside/stack.tsv"
ln -sf "$PWTEST_ROOT/outside/stack.tsv" "$WH_DIR/task/stack.tsv"
pwtest_rc 2 "stack write refuses a symlinked state file" "$(pwtest_script $SH)" stack-record "$WH" T02 parent=T01
pwtest_err 'symlink' "symlink refusal names the cause"
[ ! -s "$PWTEST_ROOT/outside/stack.tsv" ] && pwtest_ok "outside file untouched through the symlink" || pwtest_bad "symlink containment" "wrote through the symlink"
rm -rf "$PW_PROJECTS_DIR/$WH" "$PWTEST_ROOT/outside"

# --- preflight integrate: comments debt gate ---------------------------------
PRE=stackpre; rm -rf "$PW_PROJECTS_DIR/$PRE"; cp -a "$F2" "$PW_PROJECTS_DIR/$PRE"
PRE_DIR="$PW_PROJECTS_DIR/$PRE"
# baseline: F2's comments gate is green; adding a pending op must block it
pwtest_rc 0 "preflight comments green before debt" "$(pwtest_script pw-preflight.sh)" comments "$PRE"
"$(pwtest_script $SH)" stack-op "$PRE" create cascade:T02 cascade T02 sha9 "push=pending" >/dev/null 2>&1
pwtest_rc 1 "preflight comments blocked by pending stack op" "$(pwtest_script pw-preflight.sh)" comments "$PRE"
pwtest_err 'pending stack operation' "comments gate names the debt"
rm -rf "$PW_PROJECTS_DIR/$PRE"

# --- pass 2: exec after a fully landed stack targets the ultimate base --------
EX2=stackex2; EX2_DIR="$(stack_mkproj "$EX2")"
pwtest_repo ex2repo
_stack_branch_from ex2repo "agent/$EX2/T01-$EX2" master
_stack_branch_from ex2repo "agent/$EX2/T02-$EX2" "agent/$EX2/T01-$EX2"
: > "$EX2_DIR/task/PLAN.md"
stack_task "$EX2_DIR" T01 ex2repo master "agent/$EX2/T01-$EX2" none none done
stack_task "$EX2_DIR" T02 ex2repo master "agent/$EX2/T02-$EX2" T01 T01 done
printf 'ex2-1\n' > "$ROOT/ev-ex2-1"; printf 'ex2-2\n' > "$ROOT/ev-ex2-2"; printf 'ex2-2b\n' > "$ROOT/ev-ex2-2b"
printf 'stacked child MR\n' > "$ROOT/desc-stack2.md"
pwtest_rc 0 "P2 exec: verify T01" "$(pwtest_script $SH)" stack-verify "$EX2" T01 "$ROOT/ev-ex2-1"
pwtest_rc 0 "P2 exec: verify T02" "$(pwtest_script $SH)" stack-verify "$EX2" T02 "$ROOT/ev-ex2-2"
git -C "$PW_REPOS/ex2repo" checkout -q master
git -C "$PW_REPOS/ex2repo" merge -q --no-ff "agent/$EX2/T01-$EX2" -m "merge T01"
git -C "$PW_REPOS/ex2repo" push -q origin master
pwtest_rc 0 "P2 exec: land T01 (merge into master)" "$(pwtest_script $SH)" stack-land "$EX2" T01 "$(git -C "$PW_REPOS/ex2repo" rev-parse master)" master merge
pwtest_eq "P2 exec: landing recovery ref retained" \
  "$(git -C "$PW_REPOS/ex2repo" rev-parse "refs/pw-stack-landed/$EX2/T01" 2>/dev/null || true)" \
  "$(_st_get "$EX2_DIR" T01 verified_head)"
pwtest_rc 0 "P2 exec: promote T02" "$(pwtest_script $SH)" stack-promote "$EX2" T02
pwtest_re '^promote\|master$' "P2 exec: child promotes to the ultimate base"
pwtest_rc 2 "P2 exec: stale tuple (old target context) blocks shipping" "$(pwtest_script $SH)" exec "$EX2" T02 "$ROOT/desc-stack2.md"
pwtest_rc 0 "P2 exec: re-verify T02 against the ultimate target" "$(pwtest_script $SH)" stack-verify "$EX2" T02 "$ROOT/ev-ex2-2b"
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "P2 exec: ship the child after the parent landed (no ancestor branch to match)" "$(pwtest_script $SH)" exec "$EX2" T02 "$ROOT/desc-stack2.md"
grep -q "target-branch master" "$PWTEST_FORGE_LOG" \
  && pwtest_ok "P2 exec: MR create targeted the ultimate base" \
  || pwtest_bad "P2 exec ultimate target" "$(tr '\n' ';' < "$PWTEST_FORGE_LOG")"
# Branch deletion after landing: the retained ref keeps the proof resolvable and re-land is idempotent.
git -C "$PW_REPOS/ex2repo" branch -D "agent/$EX2/T01-$EX2" >/dev/null 2>&1 || true
git -C "$PW_REPOS/ex2repo" push -q origin --delete "agent/$EX2/T01-$EX2" >/dev/null 2>&1 || true
pwtest_rc 0 "P2 exec: re-land after branch deletion stays provable" "$(pwtest_script $SH)" stack-land "$EX2" T01 "$(git -C "$PW_REPOS/ex2repo" rev-parse master)" master merge
pwtest_re 'landed \(merge into master, verified\)' "P2 exec: re-land re-confirms via the retained proof"
rm -rf "$PW_PROJECTS_DIR/$EX2"

# --- pass 2: retarget recovery — raced readback + no duplicate writes ---------
REC=stackrec; REC_DIR="$(stack_mkproj "$REC")"
{ printf '# %s\n\n- **Status:** executing\n\n' "$REC"
  printf '## Merge requests\n\n| Task | Repo | MR | Target branch | State | Build |\n|------|------|----|--------------|-------|-------|\n| | | | | open / on-hold / merged | — |\n'
} > "$REC_DIR/README.md"
pwtest_repo recrepo
_stack_branch_from recrepo "agent/$REC/T01-$REC" master
_stack_branch_from recrepo "agent/$REC/T02-$REC" "agent/$REC/T01-$REC"
stack_task "$REC_DIR" T01 recrepo master "agent/$REC/T01-$REC" none none done
stack_task "$REC_DIR" T02 recrepo master "agent/$REC/T02-$REC" T01 T01 done
printf 'rec1\n' > "$ROOT/ev-rec-1"; printf 'rec2\n' > "$ROOT/ev-rec-2"
pwtest_rc 0 "P2 retarget: verify T01" "$(pwtest_script $SH)" stack-verify "$REC" T01 "$ROOT/ev-rec-1"
pwtest_rc 0 "P2 retarget: verify T02" "$(pwtest_script $SH)" stack-verify "$REC" T02 "$ROOT/ev-rec-2"
git -C "$PW_REPOS/recrepo" checkout -q master
git -C "$PW_REPOS/recrepo" merge -q --no-ff "agent/$REC/T01-$REC" -m "merge T01"
git -C "$PW_REPOS/recrepo" push -q origin master
pwtest_rc 0 "P2 retarget: land T01" "$(pwtest_script $SH)" stack-land "$REC" T01 "$(git -C "$PW_REPOS/recrepo" rev-parse master)" master merge
git -C "$PW_REPOS/recrepo" worktree add "$REC_DIR/worktree/recrepo/T02-$REC" "agent/$REC/T02-$REC" >/dev/null 2>&1 || true
printf '\n## Result\n- **MR:** https://gitlab.example.com/pwtest/recrepo/-/merge_requests/66\n' >> "$REC_DIR/task/T02.md"
printf '66 agent/%s/T01-%s\n' "$REC" "$REC" > "$PWTEST_ROOT/rec-targets"
export PWTEST_MR_TARGETS_FILE="$PWTEST_ROOT/rec-targets"
: > "$PWTEST_FORGE_LOG"
# (1) the forge write lands, but an external change supersedes it before the readback
export PWTEST_MR_SABOTAGE_TARGET="agent/$REC/T01-$REC"
pwtest_rc 2 "P2 retarget: raced readback keeps the row pending (no local write)" "$(pwtest_script $SH)" stack-retarget "$REC" T02 --apply
pwtest_err 'raced the write' "P2 retarget: raced write names the external change"
pwtest_eq "P2 retarget: local target NOT updated after the race" "$(_st_get "$REC_DIR" T02 target)" "agent/$REC/T01-$REC"
pwtest_eq "P2 retarget: recovery row retained pending" "$(awk -F'\t' '$1=="retarget:T02"{print $8}' "$REC_DIR/task/stack-ops.tsv")" "pending"
pwtest_eq "P2 retarget: pending row carries the exact desired target" "$(awk -F'\t' '$1=="retarget:T02"{print $5}' "$REC_DIR/task/stack-ops.tsv")" "master"
pwtest_eq "P2 retarget: one forge write so far" "$(grep -c 'mr update' "$PWTEST_FORGE_LOG" || true)" "1"
unset PWTEST_MR_SABOTAGE_TARGET
# (2) resume: the raced target is still wrong, so ONE more write is correct and completes
pwtest_rc 0 "P2 retarget: resume completes the raced retarget" "$(pwtest_script $SH)" stack-retarget "$REC" T02 --apply
pwtest_eq "P2 retarget: op done after resume" "$(awk -F'\t' '$1=="retarget:T02"{print $8}' "$REC_DIR/task/stack-ops.tsv")" "done"
pwtest_eq "P2 retarget: op expected survives resume" "$(awk -F'\t' '$1=="retarget:T02"{print $5}' "$REC_DIR/task/stack-ops.tsv")" "master"
pwtest_eq "P2 retarget: two writes total (the raced one corrected)" "$(grep -c 'mr update' "$PWTEST_FORGE_LOG" || true)" "2"
# (3) genuine crash window: the forge already carries the desired target AND the local target
# was already written, but the row never got marked done. Resume must finish with ZERO new writes.
pwtest_rc 0 "P2 retarget: drill — reset the local target" "$(pwtest_script $SH)" stack-record "$REC" T02 "target=agent/$REC/T01-$REC"
printf '66 master\n' > "$PWTEST_ROOT/rec-targets"
pwtest_rc 0 "P2 retarget: drill — pending row over a correct forge and stale local target" "$(pwtest_script $SH)" stack-op "$REC" create retarget:T02 promote T02 retarget "retarget=pending" master
pwtest_eq "P2 retarget: drill row pending before the action" "$(awk -F'\t' '$1=="retarget:T02"{print $8}' "$REC_DIR/task/stack-ops.tsv")" "pending"
pwtest_eq "P2 retarget: drill expected is the desired target before the action" "$(awk -F'\t' '$1=="retarget:T02"{print $5}' "$REC_DIR/task/stack-ops.tsv")" "master"
pwtest_rc 0 "P2 retarget: crash-window resume completes" "$(pwtest_script $SH)" stack-retarget "$REC" T02 --apply
pwtest_eq "P2 retarget: crash-window resume wrote NOTHING to the forge" "$(grep -c 'mr update' "$PWTEST_FORGE_LOG" || true)" "2"
pwtest_eq "P2 retarget: crash-window target recovered" "$(_st_get "$REC_DIR" T02 target)" "master"
pwtest_eq "P2 retarget: crash-window row done" "$(awk -F'\t' '$1=="retarget:T02"{print $8}' "$REC_DIR/task/stack-ops.tsv")" "done"
# (4) mirror failure after remote+state success: loud, pending, never done; resume repairs it
cp "$REC_DIR/README.md" "$REC_DIR/README.keep"
rm -f "$REC_DIR/README.md"; mkdir "$REC_DIR/README.md"
printf '66 agent/%s/T01-%s\n' "$REC" "$REC" > "$PWTEST_ROOT/rec-targets"
pwtest_rc 0 "P2 retarget: drill — reset the local target for the mirror failure" "$(pwtest_script $SH)" stack-record "$REC" T02 "target=agent/$REC/T01-$REC"
"$(pwtest_script $SH)" stack-op "$REC" create retarget:T02 promote T02 retarget "retarget=pending" master >/dev/null 2>&1
pwtest_rc 2 "P2 retarget: mirror failure after the forge write is loud and pending" "$(pwtest_script $SH)" stack-retarget "$REC" T02 --apply
pwtest_err 'dashboard mirror failed' "P2 retarget: mirror failure names the pending mirror"
pwtest_eq "P2 retarget: state target updated before the mirror failure" "$(_st_get "$REC_DIR" T02 target)" "master"
pwtest_eq "P2 retarget: row still pending after the mirror failure" "$(awk -F'\t' '$1=="retarget:T02"{print $8}' "$REC_DIR/task/stack-ops.tsv")" "pending"
pwtest_eq "P2 retarget: three writes total (the mirror failure wrote once)" "$(grep -c 'mr update' "$PWTEST_FORGE_LOG" || true)" "3"
rmdir "$REC_DIR/README.md"; mv "$REC_DIR/README.keep" "$REC_DIR/README.md"
pwtest_rc 0 "P2 retarget: resume repairs the mirror without another forge write" "$(pwtest_script $SH)" stack-retarget "$REC" T02 --apply
pwtest_eq "P2 retarget: mirror repaired, row done" "$(awk -F'\t' '$1=="retarget:T02"{print $8}' "$REC_DIR/task/stack-ops.tsv")" "done"
pwtest_eq "P2 retarget: no duplicate forge write after the mirror repair" "$(grep -c 'mr update' "$PWTEST_FORGE_LOG" || true)" "3"
# (5) head-move race: an external push lands during the retarget; the head readback must refuse
printf '66 agent/%s/T01-%s\n' "$REC" "$REC" > "$PWTEST_ROOT/rec-targets"
pwtest_rc 0 "P2 retarget: drill — reset the local target for the head race" "$(pwtest_script $SH)" stack-record "$REC" T02 "target=agent/$REC/T01-$REC"
"$(pwtest_script $SH)" stack-op "$REC" create retarget:T02 promote T02 retarget "retarget=pending" master >/dev/null 2>&1
printf '66 dead000f\n' > "$PWTEST_ROOT/rec-heads"
export PWTEST_MR_HEAD_FILE="$PWTEST_ROOT/rec-heads"
export PWTEST_MR_HEAD_SABOTAGE=beef1234
pwtest_rc 2 "P2 retarget: an external head move during the write is refused" "$(pwtest_script $SH)" stack-retarget "$REC" T02 --apply
pwtest_err 'head moved during the retarget' "P2 retarget: head-move refusal names the external push"
pwtest_eq "P2 retarget: head-move race keeps the row pending" "$(awk -F'\t' '$1=="retarget:T02"{print $8}' "$REC_DIR/task/stack-ops.tsv")" "pending"
pwtest_eq "P2 retarget: head-move race wrote the forge once (four total)" "$(grep -c 'mr update' "$PWTEST_FORGE_LOG" || true)" "4"
unset PWTEST_MR_HEAD_SABOTAGE
pwtest_rc 0 "P2 retarget: resume after the head move completes" "$(pwtest_script $SH)" stack-retarget "$REC" T02 --apply
pwtest_eq "P2 retarget: head-move resume done" "$(awk -F'\t' '$1=="retarget:T02"{print $8}' "$REC_DIR/task/stack-ops.tsv")" "done"
pwtest_eq "P2 retarget: head-move resume did not rewrite the forge" "$(grep -c 'mr update' "$PWTEST_FORGE_LOG" || true)" "4"
unset PWTEST_MR_HEAD_FILE
# (6) destination unpublished: refused BEFORE any forge write or recovery row
pwtest_rc 0 "P2 retarget: drill — reset the local target for the unpublished destination" "$(pwtest_script $SH)" stack-record "$REC" T02 "target=agent/$REC/T01-$REC"
git -C "$PWTEST_ROOT/seeds/recrepo.git" config receive.denyDeleteCurrent ignore
git -C "$PW_REPOS/recrepo" push -q origin --delete master
pwtest_rc 1 "P2 retarget: unpublished destination blocks" "$(pwtest_script $SH)" stack-retarget "$REC" T02 --apply
pwtest_re '^block\|promotion target .master. is not published' "P2 retarget: block names the unpublished destination"
pwtest_eq "P2 retarget: no forge write for an unpublished destination" "$(grep -c 'mr update' "$PWTEST_FORGE_LOG" || true)" "4"
unset PWTEST_MR_TARGETS_FILE
rm -rf "$PW_PROJECTS_DIR/$REC"

# --- pass 2: deterministic cascade A -> B -> C (shipped descendants) ----------
CC=stackcas; CC_DIR="$(stack_mkproj "$CC")"
pwtest_repo casrepo
_stack_branch_from casrepo "agent/$CC/T01-$CC" master
_stack_branch_from casrepo "agent/$CC/T02-$CC" "agent/$CC/T01-$CC"
_stack_branch_from casrepo "agent/$CC/T03-$CC" "agent/$CC/T02-$CC"
stack_task "$CC_DIR" T01 casrepo master "agent/$CC/T01-$CC" none none done
stack_task "$CC_DIR" T02 casrepo master "agent/$CC/T02-$CC" T01 T01 done
stack_task "$CC_DIR" T03 casrepo master "agent/$CC/T03-$CC" T02 T02 done
printf '\n## Result\n- **MR:** https://gitlab.example.com/pwtest/casrepo/-/merge_requests/55\n' >> "$CC_DIR/task/T02.md"
printf '\n## Result\n- **MR:** https://gitlab.example.com/pwtest/casrepo/-/merge_requests/56\n' >> "$CC_DIR/task/T03.md"
printf '55 agent/%s/T01-%s\n56 agent/%s/T02-%s\n' "$CC" "$CC" "$CC" "$CC" > "$PWTEST_ROOT/cc-targets"
export PWTEST_MR_TARGETS_FILE="$PWTEST_ROOT/cc-targets"
printf 'cc1\n' > "$ROOT/ev-cc-1"
pwtest_rc 0 "P2 cascade: verify the root T01" "$(pwtest_script $SH)" stack-verify "$CC" T01 "$ROOT/ev-cc-1"
# upstream fix on T01 (no comments anywhere in this project)
_stack_advance casrepo "agent/$CC/T01-$CC"
printf 'cc1b\n' > "$ROOT/ev-cc-1b"
pwtest_rc 0 "P2 cascade: re-verify the fixed root" "$(pwtest_script $SH)" stack-verify "$CC" T01 "$ROOT/ev-cc-1b"
FIX1="$(git -C "$PW_REPOS/casrepo" rev-parse "agent/$CC/T01-$CC")"
# B runs through its mounted worktree; C through the shared clone (both integration paths)
git -C "$PW_REPOS/casrepo" worktree add "$CC_DIR/worktree/casrepo/T02-$CC" "agent/$CC/T02-$CC" >/dev/null 2>&1 || true
ORIG_B="$(git -C "$PW_REPOS/casrepo" rev-parse "agent/$CC/T02-$CC")"
pwtest_rc 1 "P2 cascade: publication not authorized leaves push/describe pending" "$(pwtest_script $SH)" stack-cascade "$CC" T01 --verify-cmd 'echo verify-ok' --evidence-dir "$ROOT/cc-ev"
pwtest_eq "P2 cascade: op expected records the exact root verified sha" "$(awk -F'\t' '$1 ~ /^cascade:T01:/{print $5}' "$CC_DIR/task/stack-ops.tsv")" "$FIX1"
pwtest_eq "P2 cascade: B unpublished without --push (origin unchanged)" "$(git -C "$PW_REPOS/casrepo" rev-parse "origin/agent/$CC/T02-$CC")" "$ORIG_B"
git -C "$PW_REPOS/casrepo" merge-base --is-ancestor "$FIX1" "agent/$CC/T02-$CC" \
  && pwtest_ok "P2 cascade: B contains the upstream fix" || pwtest_bad "P2 cascade B integration" "B lacks $FIX1"
git -C "$PW_REPOS/casrepo" merge-base --is-ancestor "$FIX1" "agent/$CC/T03-$CC" \
  && pwtest_ok "P2 cascade: C contains the upstream fix transitively" || pwtest_bad "P2 cascade C integration" "C lacks $FIX1"
pwtest_eq "P2 cascade: B verify tuple bound to its head" "$(_st_get "$CC_DIR" T02 verified_head)" "$(git -C "$PW_REPOS/casrepo" rev-parse "agent/$CC/T02-$CC")"
pwtest_eq "P2 cascade: B inherited bullet (one)" "$(grep -c '^- \*\*Inherited:\*\* T01 @' "$CC_DIR/task/T02.md" || true)" "1"
# The writer itself is idempotent (a crash between the bullet write and the stage write must not
# duplicate evidence on retry): calling it twice for the same parent keeps exactly one bullet.
"$(pwtest_script $SH)" stack-inherited "$CC" T02 T01 "$FIX1" >/dev/null 2>&1
"$(pwtest_script $SH)" stack-inherited "$CC" T02 T01 "$FIX1" >/dev/null 2>&1
pwtest_eq "P2 cascade: re-running the inherited writer keeps one bullet" "$(grep -c '^- \*\*Inherited:\*\* T01 @' "$CC_DIR/task/T02.md" || true)" "1"
pwtest_eq "P2 cascade: C inherited bullet (one)" "$(grep -c '^- \*\*Inherited:\*\* T02 @' "$CC_DIR/task/T03.md" || true)" "1"
grep -q 'inherited update, no reviewer request' "$CC_DIR/task/T02.md" \
  && pwtest_ok "P2 cascade: inherited evidence is not a reviewer comment" || pwtest_bad "P2 cascade evidence" "missing the inherited marker text"
pwtest_eq "P2 cascade: no forged comment references" "$(grep -c '#note_\|discussion_r' "$CC_DIR/task/T02.md" "$CC_DIR/task/T03.md" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')" "0"
# resume with --push: pushes both shipped descendants; describe debt stays pending for the command layer
B1="$(git -C "$PW_REPOS/casrepo" rev-parse "agent/$CC/T02-$CC")"
pwtest_rc 1 "P2 cascade: --push publishes both; describe debt remains" "$(pwtest_script $SH)" stack-cascade "$CC" T01 --push --verify-cmd 'echo verify-ok' --evidence-dir "$ROOT/cc-ev"
pwtest_eq "P2 cascade: B pushed" "$(git -C "$PW_REPOS/casrepo" rev-parse "origin/agent/$CC/T02-$CC")" "$B1"
pwtest_err 'T02:describe=pending' "P2 cascade: describe stage kept pending (history delivery owns it)"
pwtest_eq "P2 cascade: no duplicate merge on resume" "$(git -C "$PW_REPOS/casrepo" rev-parse "agent/$CC/T02-$CC")" "$B1"
pwtest_eq "P2 cascade: inherited bullet still one after resume" "$(grep -c '^- \*\*Inherited:\*\* T01 @' "$CC_DIR/task/T02.md" || true)" "1"
# command layer completes the description debt (simulated) -> cascade done
"$(pwtest_script $SH)" stack-op "$CC" set "cascade:T01:$(printf '%s' "$(_st_get "$CC_DIR" T01 verified_head)" | cut -c1-7)" "T02:describe=done;T03:describe=done" >/dev/null 2>&1
pwtest_rc 0 "P2 cascade: done after the description debt clears" "$(pwtest_script $SH)" stack-cascade "$CC" T01 --push --verify-cmd 'echo verify-ok' --evidence-dir "$ROOT/cc-ev"
# a NEW upstream fix is a NEW bounded event: a fresh op key; the completed row stays untouched
OLD_KEY="cascade:T01:$(printf '%s' "$(_st_get "$CC_DIR" T01 verified_head)" | cut -c1-7)"
OLD_STAGES="$(awk -F'\t' -v k="$OLD_KEY" '$1==k{print $7}' "$CC_DIR/task/stack-ops.tsv")"
_stack_advance casrepo "agent/$CC/T01-$CC"
printf 'cc1c\n' > "$ROOT/ev-cc-1c"
pwtest_rc 0 "P2 cascade: re-verify after a second upstream fix" "$(pwtest_script $SH)" stack-verify "$CC" T01 "$ROOT/ev-cc-1c"
FIX2="$(git -C "$PW_REPOS/casrepo" rev-parse "agent/$CC/T01-$CC")"
NEW_KEY="cascade:T01:$(printf '%s' "$(_st_get "$CC_DIR" T01 verified_head)" | cut -c1-7)"
[ "$NEW_KEY" != "$OLD_KEY" ] && pwtest_ok "P2 cascade: second fix mints a new event key" || pwtest_bad "P2 cascade event key" "key did not change: $NEW_KEY"
pwtest_rc 1 "P2 cascade: the second event propagates (describe debt again)" "$(pwtest_script $SH)" stack-cascade "$CC" T01 --push --verify-cmd 'echo verify-ok' --evidence-dir "$ROOT/cc-ev"
pwtest_eq "P2 cascade: one row per event" "$(grep -c '^cascade:T01:' "$CC_DIR/task/stack-ops.tsv")" "2"
pwtest_eq "P2 cascade: old event row untouched" "$(awk -F'\t' -v k="$OLD_KEY" '$1==k{print $7}' "$CC_DIR/task/stack-ops.tsv")" "$OLD_STAGES"
pwtest_eq "P2 cascade: new event expected records the second root sha" "$(awk -F'\t' -v k="$NEW_KEY" '$1==k{print $5}' "$CC_DIR/task/stack-ops.tsv")" "$FIX2"
git -C "$PW_REPOS/casrepo" merge-base --is-ancestor "$FIX2" "agent/$CC/T02-$CC" \
  && pwtest_ok "P2 cascade: B carries the second fix" || pwtest_bad "P2 cascade new event" "B lacks $FIX2"
unset PWTEST_MR_TARGETS_FILE
rm -rf "$PW_PROJECTS_DIR/$CC"

# --- pass 2: a verify failure at B blocks C's subtree --------------------------
CF=stackcf; CF_DIR="$(stack_mkproj "$CF")"
pwtest_repo cfrepo
_stack_branch_from cfrepo "agent/$CF/T01-$CF" master
_stack_branch_from cfrepo "agent/$CF/T02-$CF" "agent/$CF/T01-$CF"
_stack_branch_from cfrepo "agent/$CF/T03-$CF" "agent/$CF/T02-$CF"
stack_task "$CF_DIR" T01 cfrepo master "agent/$CF/T01-$CF" none none done
stack_task "$CF_DIR" T02 cfrepo master "agent/$CF/T02-$CF" T01 T01 done
stack_task "$CF_DIR" T03 cfrepo master "agent/$CF/T03-$CF" T02 T02 done
printf 'cf1\n' > "$ROOT/ev-cf-1"
pwtest_rc 0 "P2 block: verify the root" "$(pwtest_script $SH)" stack-verify "$CF" T01 "$ROOT/ev-cf-1"
_stack_advance cfrepo "agent/$CF/T01-$CF"
printf 'cf1b\n' > "$ROOT/ev-cf-1b"
pwtest_rc 0 "P2 block: re-verify the fixed root" "$(pwtest_script $SH)" stack-verify "$CF" T01 "$ROOT/ev-cf-1b"
C_BEFORE="$(git -C "$PW_REPOS/cfrepo" rev-parse "agent/$CF/T03-$CF")"
pwtest_rc 2 "P2 block: B verification failure aborts the subtree" "$(pwtest_script $SH)" stack-cascade "$CF" T01 --verify-cmd 'case "$(git branch --show-current)" in *T02*) echo boom; exit 1 ;; *) echo ok ;; esac' --evidence-dir "$ROOT/cf-ev"
pwtest_err 'T02:verify=blocked' "P2 block: B stage is blocked"
pwtest_err 'T03:integrate=blocked' "P2 block: C's integration never ran"
pwtest_eq "P2 block: C branch untouched" "$(git -C "$PW_REPOS/cfrepo" rev-parse "agent/$CF/T03-$CF")" "$C_BEFORE"
pwtest_eq "P2 block: B local merge kept for inspection" "$(git -C "$PW_REPOS/cfrepo" merge-base --is-ancestor "$(git -C "$PW_REPOS/cfrepo" rev-parse "agent/$CF/T01-$CF")" "agent/$CF/T02-$CF" && echo kept)" "kept"
pwtest_eq "P2 block: op state blocked" "$(awk -F'\t' '$1 ~ /^cascade:T01:/{print $8}' "$CF_DIR/task/stack-ops.tsv")" "blocked"
# resume after the task is fixed: the blocked stage re-runs and terminates — no permanent block
: > "$ROOT/cf-fixed"
pwtest_rc 0 "P2 block: resume after the fix completes the cascade" "$(pwtest_script $SH)" stack-cascade "$CF" T01 --verify-cmd "case \"\$(git branch --show-current)\" in *T02*) test -f \"$ROOT/cf-fixed\" && echo fixed-ok ;; *) echo ok ;; esac" --evidence-dir "$ROOT/cf-ev"
pwtest_eq "P2 block: no blocked stage survives the resume" "$(awk -F'\t' '$1 ~ /^cascade:T01:/{print $7}' "$CF_DIR/task/stack-ops.tsv" | grep -c '=blocked' || true)" "0"
pwtest_eq "P2 block: op state done after the resume" "$(awk -F'\t' '$1 ~ /^cascade:T01:/{print $8}' "$CF_DIR/task/stack-ops.tsv")" "done"
git -C "$PW_REPOS/cfrepo" merge-base --is-ancestor "$(git -C "$PW_REPOS/cfrepo" rev-parse "agent/$CF/T01-$CF")" "agent/$CF/T03-$CF" \
  && pwtest_ok "P2 block: C integrated after the resume" || pwtest_bad "P2 block resume" "C lacks the fix"
rm -rf "$PW_PROJECTS_DIR/$CF"

# --- pass 2: unstarted descendants skip terminally; branches rehydrate safely ----
UN=stackun; UN_DIR="$(stack_mkproj "$UN")"
pwtest_repo unrepo
_stack_branch_from unrepo "agent/$UN/T01-$UN" master
_stack_branch_from unrepo "agent/$UN/T02-$UN" "agent/$UN/T01-$UN"
_stack_branch_from unrepo "agent/$UN/T04-$UN" "agent/$UN/T02-$UN"
stack_task "$UN_DIR" T01 unrepo master "agent/$UN/T01-$UN" none none done
stack_task "$UN_DIR" T02 unrepo master "agent/$UN/T02-$UN" T01 T01 done
stack_task "$UN_DIR" T03 unrepo master "agent/$UN/T03-$UN" T02 T02 todo   # unstarted: no branch anywhere
stack_task "$UN_DIR" T04 unrepo master "agent/$UN/T04-$UN" T02 T02 done
printf 'un1\n' > "$ROOT/ev-un-1"
pwtest_rc 0 "P2 unstarted: verify the root" "$(pwtest_script $SH)" stack-verify "$UN" T01 "$ROOT/ev-un-1"
_stack_advance unrepo "agent/$UN/T01-$UN"
printf 'un1b\n' > "$ROOT/ev-un-1b"
pwtest_rc 0 "P2 unstarted: re-verify the fixed root" "$(pwtest_script $SH)" stack-verify "$UN" T01 "$ROOT/ev-un-1b"
RD_BEFORE="$(git -C "$PW_REPOS/unrepo" branch --show-current)"
RD_HEAD_BEFORE="$(git -C "$PW_REPOS/unrepo" rev-parse HEAD)"
pwtest_rc 0 "P2 unstarted: cascade skips the unstarted task and continues siblings" "$(pwtest_script $SH)" stack-cascade "$UN" T01 --verify-cmd 'echo ok' --evidence-dir "$ROOT/un-ev"
FIXUN="$(git -C "$PW_REPOS/unrepo" rev-parse "agent/$UN/T01-$UN")"
UNST="$(awk -F'\t' '$1 ~ /^cascade:T01:/{print $7}' "$UN_DIR/task/stack-ops.tsv")"
case "$UNST" in
  *'T02:integrate=done'*) pwtest_ok "P2 unstarted: the started child integrated" ;;
  *) pwtest_bad "P2 unstarted: started child" "T02 stages: $UNST" ;;
esac
case "$UNST" in
  *'T03:integrate=skipped'*'T03:verify=skipped'*'T03:record=skipped'*) pwtest_ok "P2 unstarted: every T03 stage is terminal skipped" ;;
  *) pwtest_bad "P2 unstarted: T03 skip" "T03 stages: $UNST" ;;
esac
case "$UNST" in
  *'T04:integrate=done'*) pwtest_ok "P2 unstarted: the independent sibling still processed" ;;
  *) pwtest_bad "P2 unstarted: sibling" "T04 stages: $UNST" ;;
esac
pwtest_eq "P2 unstarted: op state done" "$(awk -F'\t' '$1 ~ /^cascade:T01:/{print $8}' "$UN_DIR/task/stack-ops.tsv")" "done"
pwtest_eq "P2 unstarted: T03 created no branch" "$(git -C "$PW_REPOS/unrepo" rev-parse --verify --quiet "refs/heads/agent/$UN/T03-$UN" || echo none)" "none"
pwtest_eq "P2 unstarted: T03 created no remote branch" "$(git -C "$PW_REPOS/unrepo" rev-parse --verify --quiet "refs/remotes/origin/agent/$UN/T03-$UN" || echo none)" "none"
[ ! -e "$UN_DIR/worktree/unrepo/T03-$UN" ] && pwtest_ok "P2 unstarted: T03 has no worktree" || pwtest_bad "P2 unstarted: T03 worktree" "a worktree was created"
pwtest_eq "P2 unstarted: T03 prerequisite head recorded for spawn" "$(_st_get "$UN_DIR" T03 consumed_parent_sha)" "$(git -C "$PW_REPOS/unrepo" rev-parse "agent/$UN/T02-$UN")"
pwtest_eq "P2 unstarted: no fabricated verification for T03" "$(_st_get "$UN_DIR" T03 verified_head)" ""
grep -q 'Inherited' "$UN_DIR/task/T03.md" && pwtest_bad "P2 unstarted: T03 evidence" "an inherited bullet was written" || pwtest_ok "P2 unstarted: T03 task file left untouched"
pwtest_eq "P2 unstarted: shared clone checkout untouched" "$(git -C "$PW_REPOS/unrepo" branch --show-current)" "$RD_BEFORE"
pwtest_eq "P2 unstarted: shared clone HEAD untouched" "$(git -C "$PW_REPOS/unrepo" rev-parse HEAD)" "$RD_HEAD_BEFORE"
[ -d "$UN_DIR/worktree/unrepo/T02-$UN" ] && pwtest_ok "P2 unstarted: T02 worktree rehydrated at the approved location" || pwtest_bad "P2 unstarted: T02 rehydrate" "no worktree"
[ -d "$UN_DIR/worktree/unrepo/T04-$UN" ] && pwtest_ok "P2 unstarted: T04 worktree rehydrated at the approved location" || pwtest_bad "P2 unstarted: T04 rehydrate" "no worktree"
git -C "$PW_REPOS/unrepo" merge-base --is-ancestor "$FIXUN" "agent/$UN/T02-$UN" \
  && pwtest_ok "P2 unstarted: T02 carries the fix" || pwtest_bad "P2 unstarted: T02 fix" "T02 lacks $FIXUN"
git -C "$PW_REPOS/unrepo" merge-base --is-ancestor "$FIXUN" "agent/$UN/T04-$UN" \
  && pwtest_ok "P2 unstarted: T04 carries the fix transitively" || pwtest_bad "P2 unstarted: T04 fix" "T04 lacks $FIXUN"
# the cascade's skip record (parent + consumed head, no tuple) must preview as UNVERIFIED, not
# stale — an unstarted descendant never blocks its ancestors' incremental shipping
pwtest_rc 0 "P2 unstarted: preview after the cascade" "$(pwtest_script $SH)" stack "$UN"
pwtest_re '^T03\|T02\|.*\|.*\|master\|no\|unverified\|0' "P2 unstarted: T03 reads unverified (not stale) after the skip record"
rm -rf "$PW_PROJECTS_DIR/$UN"

# --- pass 2: worktree reattach needs a binding AND the current parent head -------
WA=stackwa; WA_DIR="$(stack_mkproj "$WA")"
pwtest_repo warepo "branch:agent/$WA/T01-$WA"
stack_task "$WA_DIR" T01 warepo master "agent/$WA/T01-$WA" none none done
stack_task "$WA_DIR" T02 warepo master "agent/$WA/T02-$WA" T01 T01 todo
printf 'wa1\n' > "$ROOT/ev-wa-1"
pwtest_rc 0 "P2 attach: verify T01" "$(pwtest_script $SH)" stack-verify "$WA" T01 "$ROOT/ev-wa-1"
pwtest_rc 0 "P2 attach: create the child worktree" "$(pwtest_script pw-worktree.sh)" create "$WA" T02 warepo master
git -C "$PW_REPOS/warepo" worktree remove "$WA_DIR/worktree/warepo/T02-$WA" >/dev/null 2>&1 || true
# the parent advances and is re-verified; the child branch lacks the new tip -> deny
_stack_advance warepo "agent/$WA/T01-$WA"
printf 'wa1b\n' > "$ROOT/ev-wa-1b"
pwtest_rc 0 "P2 attach: re-verify the advanced parent" "$(pwtest_script $SH)" stack-verify "$WA" T01 "$ROOT/ev-wa-1b"
pwtest_rc 2 "P2 attach: a child that predates the verified parent head cannot reattach" "$(pwtest_script pw-worktree.sh)" create "$WA" T02 warepo master
pwtest_err 'predates' "P2 attach: refusal names the advanced parent head"
# merge the new parent tip into the child, then the reattach is allowed
git -C "$PW_REPOS/warepo" checkout -q "agent/$WA/T02-$WA"
git -C "$PW_REPOS/warepo" merge -q --no-edit "agent/$WA/T01-$WA"
git -C "$PW_REPOS/warepo" checkout -q master
pwtest_rc 0 "P2 attach: a fresh child reattaches" "$(pwtest_script pw-worktree.sh)" create "$WA" T02 warepo master
# a stacked branch with no recorded binding is denied
git -C "$PW_REPOS/warepo" branch "agent/$WA/T03-$WA" master
stack_task "$WA_DIR" T03 warepo master "agent/$WA/T03-$WA" T01 T01 todo
pwtest_rc 2 "P2 attach: a binding-less stacked branch is denied" "$(pwtest_script pw-worktree.sh)" create "$WA" T03 warepo master
pwtest_err 'no recorded parent binding' "P2 attach: refusal names the missing binding"
# legacy (no stack) attach is unchanged
git -C "$PW_REPOS/warepo" branch "agent/$WA/T09-$WA" master
stack_task "$WA_DIR" T09 warepo master "agent/$WA/T09-$WA" none none todo
pwtest_rc 0 "P2 attach: legacy independent attach unchanged" "$(pwtest_script pw-worktree.sh)" create "$WA" T09 warepo master
rm -rf "$PW_PROJECTS_DIR/$WA"

# --- pass 2: preview token vs strict staleness at the preflight boundary ---------
# F6: a never-started stacked child (no tuple, no branch, todo) must preview as "unverified" and
# must NOT block the verified root's incremental ship; a done/accepted task without its binding,
# an explicitly stale task, and a genuinely drifted tuple must all still block.
PS=stackps; PS_DIR="$(stack_mkproj "$PS")"
pwtest_repo psrepo
_stack_branch_from psrepo "agent/$PS/T01-$PS" master
_ps_plan() {  # <T01-status> <T02-status> [T03-status]
  { echo "# $PS plan"; echo; echo "## Task breakdown"; echo
    echo "| ID | Title | Repo | depends_on | Group | Execute with | SP | Status | Time | Result |"
    echo "|----|-------|------|------------|-------|--------------|----|--------|------|--------|"
    echo "| [T01](./T01.md) | one | psrepo | — | G1 | — | 1 | $1 | — | — |"
    echo "| [T02](./T02.md) | two | psrepo | T01 | G1 | — | 1 | $2 | — | — |"
    [ -n "${3:-}" ] && echo "| [T03](./T03.md) | three | psrepo | T01 | G1 | — | 1 | $3 | — | — |"
  } > "$PS_DIR/task/PLAN.md"
}
_ps_status() { sed -E -i '' "s|^(- \*\*Status:\*\*) .*|\1 $2|" "$PS_DIR/task/$1.md"; }
stack_task "$PS_DIR" T01 psrepo master "agent/$PS/T01-$PS" none none done
stack_task "$PS_DIR" T02 psrepo master "agent/$PS/T02-$PS" T01 T01 todo
_ps_plan done todo
printf 'ps1\n' > "$ROOT/ev-ps-1"
# (1) a done root participant without its tuple must bind before shipping (never exempted)
pwtest_rc 1 "P2 preview: a done root without a tuple blocks ship" "$(pwtest_script pw-preflight.sh)" ship "$PS"
pwtest_err 'stale verification:T01' "P2 preview: the block names the unbound root"
# (2) root verified + child todo with no branch => the root's incremental ship is allowed
pwtest_rc 0 "P2 preview: bind the root" "$(pwtest_script $SH)" stack-verify "$PS" T01 "$ROOT/ev-ps-1"
pwtest_rc 0 "P2 preview: root ship allowed with an unstarted todo child" "$(pwtest_script pw-preflight.sh)" ship "$PS"
pwtest_rc 0 "P2 preview: stack rows" "$(pwtest_script $SH)" stack "$PS"
pwtest_re '^T02\|T01\|agent/stackps/T01-stackps\|agent/stackps/T02-stackps\|master\|no\|unverified\|0' "P2 preview: the child previews as unverified"
# (3) a done child lacking its tuple must still block
_ps_status T02 done; _ps_plan done done
pwtest_rc 1 "P2 preview: a done child without its tuple blocks" "$(pwtest_script pw-preflight.sh)" ship "$PS"
pwtest_err 'stale verification:T02' "P2 preview: the block names the unbound done child"
# (4) bind the child => fresh, ship allowed again
_stack_branch_from psrepo "agent/$PS/T02-$PS" "agent/$PS/T01-$PS"
printf 'ps2\n' > "$ROOT/ev-ps-2"
pwtest_rc 0 "P2 preview: bind the child tuple" "$(pwtest_script $SH)" stack-verify "$PS" T02 "$ROOT/ev-ps-2"
pwtest_rc 0 "P2 preview: ship allowed with fresh bindings" "$(pwtest_script pw-preflight.sh)" ship "$PS"
# (5) a genuinely drifted tuple still blocks
_stack_advance psrepo "agent/$PS/T02-$PS"
pwtest_rc 1 "P2 preview: a genuinely stale child tuple blocks" "$(pwtest_script pw-preflight.sh)" ship "$PS"
pwtest_err 'stale verification:T02' "P2 preview: the block names the drifted tuple"
pwtest_rc 0 "P2 preview: re-bind the child after the drift" "$(pwtest_script $SH)" stack-verify "$PS" T02 "$ROOT/ev-ps-2"
# (6) explicit stale + todo stays a conservative block (and clearing it restores unverified)
stack_task "$PS_DIR" T03 psrepo master "agent/$PS/T03-$PS" T01 T01 todo
_ps_plan done done todo
pwtest_rc 0 "P2 preview: an extra unstarted todo child keeps ship allowed" "$(pwtest_script pw-preflight.sh)" ship "$PS"
pwtest_rc 0 "P2 preview: force the explicit stale flag" "$(pwtest_script $SH)" stack-stale "$PS" T03
pwtest_rc 1 "P2 preview: explicit stale on a todo task blocks conservatively" "$(pwtest_script pw-preflight.sh)" ship "$PS"
pwtest_err 'stale verification:T03' "P2 preview: the explicit-stale block names T03"
pwtest_rc 0 "P2 preview: clear the explicit flag" "$(pwtest_script $SH)" stack-fresh "$PS" T03
# (7) a cascade skip record (parent + consumed head, no tuple) stays unverified, not stale
pwtest_rc 0 "P2 preview: record the cascade-style prerequisite head" "$(pwtest_script $SH)" stack-record "$PS" T03 parent=T01 "consumed_parent_sha=$(git -C "$PW_REPOS/psrepo" rev-parse "agent/$PS/T01-$PS")" "consumed_parent_branch=agent/$PS/T01-$PS"
pwtest_rc 0 "P2 preview: root ship still allowed after the skip record" "$(pwtest_script pw-preflight.sh)" ship "$PS"
pwtest_rc 0 "P2 preview: stack rows after the skip record" "$(pwtest_script $SH)" stack "$PS"
pwtest_re '^T03\|T01\|.*\|.*\|master\|no\|unverified\|0' "P2 preview: the skip record stays unverified"
pwtest_rc 0 "P2 preview: plan after the skip record" "$(pwtest_script $SH)" stack-plan "$PS"
pwtest_re '^T03\|psrepo\|agent/stackps/T03-stackps\|agent/stackps/T01-stackps\|T01\|no\|not verified yet' "P2 preview: plan marks the unstarted child not-verified (not stale)"
rm -rf "$PW_PROJECTS_DIR/$PS"
# legacy control: a project with NO stacks is unaffected by the freshness gate
LC=stacklc; LC_DIR="$(stack_mkproj "$LC")"
pwtest_repo lcrepo
stack_task "$LC_DIR" T01 lcrepo master "agent/$LC/T01-$LC" none none done
{ echo "# $LC plan"; echo; echo "## Task breakdown"; echo
  echo "| ID | Title | Repo | depends_on | Group | Execute with | SP | Status | Time | Result |"
  echo "|----|-------|------|------------|-------|--------------|----|--------|------|--------|"
  echo "| [T01](./T01.md) | one | lcrepo | — | G1 | — | 1 | done | — | — |"
} > "$LC_DIR/task/PLAN.md"
pwtest_rc 0 "P2 preview: legacy (no stacks) ship unaffected" "$(pwtest_script pw-preflight.sh)" ship "$LC"
rm -rf "$PW_PROJECTS_DIR/$LC"

# --- pass 2: CI tuple semantics after a target change --------------------------
CI2=stackci; CI2_DIR="$(stack_mkproj "$CI2")"
pwtest_repo cirepo
_stack_branch_from cirepo "agent/$CI2/T01-$CI2" master
_stack_branch_from cirepo "agent/$CI2/T02-$CI2" "agent/$CI2/T01-$CI2"
stack_task "$CI2_DIR" T01 cirepo master "agent/$CI2/T01-$CI2" none none done
stack_task "$CI2_DIR" T02 cirepo master "agent/$CI2/T02-$CI2" T01 T01 done
printf 'ci1\n' > "$ROOT/ev-ci-1"; printf 'ci2\n' > "$ROOT/ev-ci-2"; printf 'ci2b\n' > "$ROOT/ev-ci-2b"
pwtest_rc 0 "P2 ci: verify T01" "$(pwtest_script $SH)" stack-verify "$CI2" T01 "$ROOT/ev-ci-1"
pwtest_rc 0 "P2 ci: verify T02 with a target-bound green" "$(pwtest_script $SH)" stack-verify "$CI2" T02 "$ROOT/ev-ci-2" --ci-sha "$(git -C "$PW_REPOS/cirepo" rev-parse "agent/$CI2/T02-$CI2")" --ci-target "agent/$CI2/T01-$CI2"
pwtest_rc 0 "P2 ci: preview after the green bind" "$(pwtest_script $SH)" stack "$CI2"
pwtest_re '^T02\|.*\|fresh\|' "P2 ci: same-target green is fresh"
git -C "$PW_REPOS/cirepo" checkout -q master
git -C "$PW_REPOS/cirepo" merge -q --no-ff "agent/$CI2/T01-$CI2" -m "merge T01"
git -C "$PW_REPOS/cirepo" push -q origin master
pwtest_rc 0 "P2 ci: land T01" "$(pwtest_script $SH)" stack-land "$CI2" T01 "$(git -C "$PW_REPOS/cirepo" rev-parse master)" master merge
pwtest_rc 0 "P2 ci: promote T02" "$(pwtest_script $SH)" stack-promote "$CI2" T02
pwtest_rc 0 "P2 ci: preview after promotion" "$(pwtest_script $SH)" stack "$CI2"
pwtest_re '^T02\|.*\|stale\|' "P2 ci: the old target's green cannot certify the new target"
# Re-bind a FRESH tuple whose CI evidence is still tied to the old target: the ci_target context
# alone must keep it stale (this is the distinct old-target-green guard).
pwtest_rc 0 "P2 ci: re-verify with a fresh tuple but old-target CI" "$(pwtest_script $SH)" stack-verify "$CI2" T02 "$ROOT/ev-ci-2b" --ci-sha "$(git -C "$PW_REPOS/cirepo" rev-parse "agent/$CI2/T02-$CI2")" --ci-target "agent/$CI2/T01-$CI2"
pwtest_rc 0 "P2 ci: preview after the old-target CI bind" "$(pwtest_script $SH)" stack "$CI2"
pwtest_re '^T02\|.*\|stale\|' "P2 ci: a green bound to the old target context is stale even with a fresh tuple"
pwtest_rc 0 "P2 ci: re-verify with an explicit skipped disposition" "$(pwtest_script $SH)" stack-verify "$CI2" T02 "$ROOT/ev-ci-2b" --ci-sha skipped
pwtest_rc 0 "P2 ci: preview after skipped" "$(pwtest_script $SH)" stack "$CI2"
pwtest_re '^T02\|.*\|fresh\|' "P2 ci: explicit skipped keeps the tuple fresh (ship may proceed, MR reports skipped)"
pwtest_rc 0 "P2 ci: re-verify with an explicit pending disposition" "$(pwtest_script $SH)" stack-verify "$CI2" T02 "$ROOT/ev-ci-2b" --ci-sha pending
pwtest_rc 0 "P2 ci: preview after pending" "$(pwtest_script $SH)" stack "$CI2"
pwtest_re '^T02\|.*\|fresh\|' "P2 ci: explicit pending is distinct and does not block the ship gate"
pwtest_rc 0 "P2 ci: bind a mismatched CI sha" "$(pwtest_script $SH)" stack-verify "$CI2" T02 "$ROOT/ev-ci-2b" --ci-sha dead00aa
pwtest_rc 0 "P2 ci: preview after the mismatched sha" "$(pwtest_script $SH)" stack "$CI2"
pwtest_re '^T02\|.*\|stale\|' "P2 ci: a CI sha that does not match the verified head is stale"
rm -rf "$PW_PROJECTS_DIR/$CI2"

# --- pass 2: component lock fails closed on a stale lock -----------------------
LK=stacklk; LK_DIR="$(stack_mkproj "$LK")"
stack_task "$LK_DIR" T01 api master "agent/$LK/T01-$LK" none none done
mkdir -p "$LK_DIR/task/.stack.tsv.lock"
printf '999999\n' > "$LK_DIR/task/.stack.tsv.lock/pid"
printf 'stale-token\n' > "$LK_DIR/task/.stack.tsv.lock/token"
pwtest_rc 2 "P2 lock: a stale lock fails closed (never auto-reclaimed)" "$(pwtest_script $SH)" stack-record "$LK" T01 "branch=agent/$LK/T01-$LK"
pwtest_err 'never auto-reclaimed' "P2 lock: refusal explains the manual removal rule"
[ -d "$LK_DIR/task/.stack.tsv.lock" ] && pwtest_ok "P2 lock: the stale lock is left intact for the operator" || pwtest_bad "P2 lock" "lock vanished"
rm -rf "$PW_PROJECTS_DIR/$LK"

# --- pass 2: stack-state schema/version validation -----------------------------
SV=stacksv; SV_DIR="$(stack_mkproj "$SV")"
stack_task "$SV_DIR" T01 api master "agent/$SV/T01-$SV" none none done
pwtest_rc 0 "P2 schema: a fresh write creates the v1 record" "$(pwtest_script $SH)" stack-record "$SV" T01 "branch=agent/$SV/T01-$SV"
cp "$SV_DIR/task/stack.tsv" "$SV_DIR/task/stack.valid"
printf '# pw-stack-state v9 — forged\n' > "$SV_DIR/task/stack.tsv"
pwtest_rc 2 "P2 schema: an unsupported version is rejected before reads" "$(pwtest_script $SH)" stack "$SV"
pwtest_err 'unsupported state version' "P2 schema: version refusal names the reason"
cp "$SV_DIR/task/stack.valid" "$SV_DIR/task/stack.tsv"
printf 'T99\tshort\trow\n' >> "$SV_DIR/task/stack.tsv"
pwtest_rc 2 "P2 schema: a malformed row is rejected before operations" "$(pwtest_script $SH)" stack-record "$SV" T01 "branch=agent/$SV/T01-$SV"
pwtest_err 'malformed row' "P2 schema: malformed-row refusal names the reason"
rm -rf "$PW_PROJECTS_DIR/$SV"