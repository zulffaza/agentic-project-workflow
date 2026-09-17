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
`pw-mdlib.sh` — or the register itself changes). A full sweep is ~3–5 min for all 33 rows.

## The meta-test (`--mutation`)

`expectations/mutations.tsv` reverts one **documented fix** per coupling-register row (C1–C42;
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
watchdog (`PWTEST_MUT_TIMEOUT`, default 300 s): a timeout is reported as `HUNG`, the mutated file
is restored, the sweep **continues**, and the final exit lists the hung rows. Progress prints one
`MUT n/N <id> rc=<rc> <elapsed>s` line per row.

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
