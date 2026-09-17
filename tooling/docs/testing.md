# Change testing flow (the pw-test harness)

**Audience:** maintainers and agents editing anything under `tooling/`, `template/`, or the
provider surfaces. This is *protocol* — what to run when you change something, and how to read the
harness. Behavioral docs for users live in `../../docs/`; script usage in `./scripts/`.

## The one command

```bash
bash tooling/tests/pw_test.sh                 # default tiers T0,T1,T2,T4 (~2–3 min)
bash tooling/tests/pw_test.sh --tier T0       # after an edit: seconds — syntax + anti-idiom
bash tooling/tests/pw_test.sh --tier T1 --only doc-lint   # one script's unit cases
```

Exit `0` only when everything selected passed; the final `pwtest: P pass, F fail, S skip` line is
CI-greppable. `--only <pattern>` filters T1 case files. Fixtures are **generated from `template/`**
into a temp root, and only the ones the selected tiers/cases actually consume are built (plan 19):
a `--tier T0`/`--tier T4` run builds **nothing**, `--only <script>` builds just the fixture its
case clones, and `--mutation` children copy fixtures from a shared pristine cache. Nothing on disk
under `tooling/tests/` is fixture *content*, and no test writes to a real project (T3 is read-only
there; mutations sandbox by construction). Every run prints `TEST fixtures built: …` and
`TIME <section> <n>s` lines — use them to see where time goes.

| Tier | What it checks | Typical single-tier run |
|---|---|---|
| **T0** static | `bash -n` every script + the harness; `--help` on the 14 automation scripts; forbidden-idiom greps (`declare -A`, `\| xargs`, `grep -c … \|\| echo 0`, whole-file `verify-failed` greps, bare `## Tasks` anchors, `exec/bash "$0"` respawns) | ~2 s (no fixtures) |
| **T1** unit | per-script cases in `tests/cases/*.t.sh` (happy + negative + idempotency) against F1 scaffold / F2 mid-lifecycle / F3 hostile fixtures, plus the two-owner MR-URL parity case and `pw-lib`/`pw-status` selftests invoked from a foreign cwd | ~30 s |
| **T2** battery | golden matrices `expectations/battery.tsv` + `gates.tsv`: every read-only invocation and every preflight gate on every fixture, rc pinned, **`→ fix:` remediation asserted on every non-zero**, script-crash detector, and a **mode-completeness** rule (every advertised mode appears in a pinned row) | ~1 min |
| **T3** corpus | read-only battery over real projects when `--corpus-dir DIR` (or `PW_CORPUS_DIR`) is given; crash-vs-clean-failure classification with `→ fix:` contract; pre-baseline projects are clean failures advising "refresh local templates"; a current-baseline project is the golden gate; personal data issues waived via `~/.pw/test-issues.tsv` | opt-in |
| **T4** consistency | `pw-doctor` synced (run with the fixture env stripped; regen is `pw-doctor --fix` — never edit installed provider copies), registry symmetry (14 files ⇄ index ⇄ command/agent/skill wiring, allowlist `expectations/unwired.ok`), info-boundary greps, doctrine canaries (sources-only rule, FIELD-BULLET rule, phase-machine token line) | ~6 s (no fixtures) |

`pw-doctor.sh --test` delegates to `pw_test.sh` (default tiers).

## Cadence — how long, and how often

The default run (~2–3 min) is the **commit gate**, not the edit-loop gate. Inside an edit loop
run the cheap slice first: `--tier T0` (~2 s) catches syntax + every idiom that ever bit us,
`--tier T4` (~6 s) the consistency canaries, and `--tier T1 --only <script>` (seconds–30 s)
covers the script you touched; promote to the full run once before committing. Fixtures are built
only when the selected tiers consume them, so a filtered run is genuinely fast.

For the **meta-test**, scope to what you touched: `--mutation '<id-filter>'` runs only matching
register rows — during development use it per changed file (e.g. `--mutation 'C2[5-9]'`), and the
**full sweep belongs at the ship gate only** (or when a shared library — `pw-common.sh`,
`pw-mdlib.sh` — or the register itself changes). A full sweep is **~1 min** (parallel, warm cache).

## The meta-test (`--mutation`)

`expectations/mutations.tsv` reverts one **documented fix** per coupling-register row (C1–C44;
plan 16 §5, extended by plans 17/19) in the working tree and asserts the harness catches it: a
mutation that passes = a vacuous test — the exact failure mode that produced this protocol. Each
row: `id \t file(rel tooling/) \t OLD \t NEW \t tier \t only`; a drift-flagged row means the
anchor moved with the code — re-pin it, don't delete it. After adding any nontrivial fix, add a
row for its coupling and verify the one anchor: `--mutation <id>` (~5 s/row with a warm cache) or
a slice like `--mutation 'C2[5-9]'`.

Sweep mechanics (plan 19): the parent warms a **pristine fixture cache** (keyed by a hash of the
fixture *recipe*: `template/` + `scaffold.sh` + `pw-env.sh` + `pw_test_lib.sh` — deliberately NOT
the runtime scripts) and each child copies from it instead of rebuilding; cache dir
`$TMPDIR/pwtest-fixture-cache` (override `PWTEST_MUT_CACHE`, disable `PWTEST_FIXTURE_CACHE=`).
**Convention this creates: a mutation catcher must never depend on the mutation changing fixture
BYTES** — catchers test runtime readers on template-derived data. Every child runs under a
watchdog (`PWTEST_MUT_TIMEOUT`, default 300 s): a timeout is reported as `HUNG`, the sweep
**continues**, and the final exit lists the hung rows. Progress prints one
`MUT n/N <id> rc=<rc> <elapsed>s` line per row.

The sweep is **parallel by default** (`PWTEST_MUT_JOBS`, auto = min(ncpu, 8)): one worker per
row, each mutating a disposable rsync copy of the bundle (excluding `.git`) — the live tree is
never mutated, so workers cannot see each other's reverts (the false-"caught" hazard of
parallel-on-live) and same-file rows need no serialization. A full sweep is **~70 s for 35
rows**; `PWTEST_MUT_JOBS=1` keeps the original serial live-tree path.

## Inside the harness (read this before editing tests/ or writing mutation rows)

**Fixture lifecycle.** `pw_test.sh` and `selftest_entry.sh` (the per-script `--selftest` path)
materialize fixtures through exactly two functions in `pw_test_lib.sh`:

1. `_pwtest_scan <file>…` — sets `NEED_F1/2/3` when a scanned file references `$F1..$F3`,
   `$S1..$S3`, or `PWTEST_F2`. The runner scans the scripts the selected tiers actually run
   (T1: only the `--only`-matched case files). Overbuild is safe (slower); underbuild fails
   loudly (cases error on missing dirs), so the scan errs toward matching, comments included.
   `$F3` forces `$F2` — F3 is derived from F2.
2. `_pwtest_materialize` — first **clears inherited `F1..F3`/`PWTEST_F2`** (a fresh child must
   never trust a parent's exported fixture paths: they point at the *parent's* temp root — this
   exact bug shipped once and the parity gate caught it), then per `NEED_F*` either restores from
   `$PWTEST_FIXTURE_CACHE/<hash>/` or builds via `pwtest_build_f1/f2/f3`. A run that built all
   three publishes them into the cache atomically (tmp dir + `mv`).

**Cache layout** — `$TMPDIR/pwtest-fixture-cache/<hash>/` holds `projects/<slug>` per fixture,
plus `repos/` + `seeds/`, plus `.done-<slug>` markers. `<hash>` = digest of the fixture *recipe*:
`template/` tree + `scaffold.sh` + `pw-env.sh` + `pw_test_lib.sh`. Runtime scripts
(`pw-lib.sh`, `pw-common.sh`, …) are deliberately **excluded** — fixture bytes must not depend on
them (see the catcher convention above; a mutation to a runtime file must therefore not change the
cache key, which is what lets every sweep child share one warm cache). Restored `repos/` carry
absolute paths in git metadata, so `_pwtest_cache_repair` re-points F2's worktrees
(`git worktree repair`) and the clones' push-URLs (at the child's own `seeds/`). F3's worktree
copies are stale by design — identical to what a fresh build produces; don't "fix" them.

**Sweep paths.** `pwtest_run_mutations` (mutate.sh) warms the cache once (a
`PWTEST_WARM=1 PWTEST_FORCE_FIXTURES=1` child that exits right after materialization), then:

- **parallel (default, >1 row):** one `_pwtest_mut_worker` per row behind a FIFO token semaphore
  (`PWTEST_MUT_JOBS`, auto = min(ncpu, 8)). Each worker `rsync`s a **disposable copy of the
  bundle** (excluding `.git`, ~1.3 MB) and mutates only there — the live tree is never touched,
  so workers can't cross-see reverts and same-file rows need no serialization. Rows write
  `<id>\t<status>\t<elapsed>` to `results.tsv`; the parent aggregates in original row order.
- **serial (`PWTEST_MUT_JOBS=1`, or a single-row filter):** `_pwtest_run_row` against the live
  tree, wrapped in the `_pwt_mutable_push/pop` crash-safety stack so the EXIT trap can replay a
  restore if the sweep is killed mid-row. ⚠ `_pwt_mutable_pop` must rebuild into a **fresh**
  accumulator — appending to the live stack while iterating doubles its size per pop (O(2ⁿ)
  churn); that bug was the plan-17 "parent-side hang" (clean tree, child done, CPU spin).

`_pwtest_run_row` (shared by both paths) classifies each row: `caught` (harness rc 1), `hung`
(watchdog `PWTEST_MUT_TIMEOUT`, default 300 s — file restored, sweep continues), `died` (rc 2 =
child setup problem), `vacuous` (rc 0 = the catcher is toothless), `drift` (OLD anchor gone —
re-pin it against the current code, don't delete the row), `applyfail`. Child logs land in
`<keep>/<id>.child.log` (`PWTEST_KEEP_DIR` to preserve them past cleanup).

**Fixture etiquette for case authors.** Never mutate the shared `$F1..$F3` — `cp -a "$F2"
"$PW_PROJECTS_DIR/<private>"` first (the C22 pollution bug: one case editing shared F2 broke the
T2 battery later in the same run). Read-only invocations against `$S1..$S3` are fine. If a case
truly must touch a shared fixture, restore it exactly.

**Env knobs:** `PWTEST_MUT_JOBS` (parallelism; `1` = serial live-tree), `PWTEST_MUT_TIMEOUT`
(watchdog seconds), `PWTEST_MUT_CACHE` (cache dir), `PWTEST_FIXTURE_CACHE=` (disable cache),
`PWTEST_KEEP_DIR` (child-log dir), `PWTEST_VERBOSE=1`. Internal (don't set by hand):
`PWTEST_WARM`/`PWTEST_FORCE_FIXTURES` (warm pass), `PWTEST_INNER` (sweep children),
`PWTEST_MUT_NESTED` (recursion guard in `cases/pw-test-harness.t.sh`).

## Writing a mutation row

`expectations/mutations.tsv` columns: `id \t file(rel tooling/) \t OLD \t NEW \t tier \t only`.

1. `OLD` must be **byte-exact and unique** in the file — the apply step replaces *every*
   occurrence, and drift only detects absence. Check: `grep -cF '<OLD>' <file>` → `1`.
2. Pick the cheapest `tier` + `only` whose checks actually exercise the reverted fix
   (`T1` + the script's case name is the usual shape; `-` in `only` matches all T1 case names —
   every name contains a hyphen, so it is effectively "no filter").
3. The catcher must fail **iff** the mutation is applied — and must not depend on the mutation
   changing fixture BYTES (recipe-hash convention above).
4. IDs: take the next free number **and** check the register plus the draft-plan reservations
   (C31–C35 reserved by the `/pw-help` plan, C36+ by the tooling-layout plan) before minting.
5. Verify with `--mutation <your-id>` (single row → serial; ~5–60 s depending on tier) before
   committing.

## The agent protocol (change type → minimum tiers)

| Change | Must run | Must also |
|---|---|---|
| One script's internals | `--tier T0` + `--tier T1 --only <script>` while editing; default run once before commit | update its `docs/scripts/*` usage if the message/output shape moved |
| `pw-common.sh` shared readers, or any shared helper | default run (all four tiers) | consumer scripts keep their own T1 even when their code didn't change |
| `template/` (format change) | default run + **T3 corpus** (`--corpus-dir …`) | update `docs/scripts/*`; fixtures move with the template automatically — pre-change projects become corpus-side stale data whose T3 failures must stay clean `→ fix:` advisories (migrate-or-degrade is the shipping bar) |
| Commands / agents / skills (phases, gates) | regen via `pw-doctor --fix`, then `--tier T4` (+T2 if gates moved) | the same phase's gate set must appear identically in the other entry paths (commands ⇄ skill ⇄ agents); a new gate = rows in `gates.tsv`; edits go to **canonical sources only** — a fix that lives only in installed provider copies is destroyed by the next regen |
| Docs only | `--tier T4` (+T0 if you touched a script header comment) | boundary greps may fail if you leaked a script name into `docs/`; re-run after fixing |
| New/renamed automation script | default run + `--mutation <new rows>` + full `--mutation` sweep at register cadence | registry docs/scripts index, wiring in commands+lanes, `unwired.ok` only with a written reason, ≥1 coupling row + ≥1 mutation |
| Before commit/push of any of the above | default run; targeted `--mutation <new rows>` at least | report tier counts in the commit message |
| User-facing behavior changed (error text, exit code) | re-pin deliberately: `--capture battery` (or `gates`/`both`), **review the diff** — an rc silently moving is a contract change | never weaken an assertion to make a tier go green without recording why |

If `pw_test.sh` fails and you suspect the *test* is wrong, the register and the fix-commit history
(see `tooling/README.md` + the improvements plan) say which side is authoritative. The harness
itself has been caught containing vacuous checks (the T0 idiom table shipped with tab-prefixed
regexes and a literal-`|` field separator that made it silent for ~10 min of its own existence —
`--mutation` found it) — `--mutation` is the guard; extend it with every fix.
