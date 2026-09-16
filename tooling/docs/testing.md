# Change testing flow (the pw-test harness)

**Audience:** maintainers and agents editing anything under `tooling/`, `template/`, or the
provider surfaces. This is *protocol* — what to run when you change something, and how to read the
harness. Behavioral docs for users live in `../../docs/`; script usage in `./scripts/`.

## The one command

```bash
bash tooling/tests/pw_test.sh                 # default tiers T0,T1,T2,T4 (~3–4 min)
bash tooling/tests/pw_test.sh --tier T0       # after an edit: seconds — syntax + anti-idiom
bash tooling/tests/pw_test.sh --tier T1 --only doc-lint   # one script's unit cases
```

Exit `0` only when everything selected passed; the final `pwtest: P pass, F fail, S skip` line is
CI-greppable. `--only <pattern>` filters T1 case files. Fixtures are **generated from `template/`
on every run** into a temp root — nothing on disk under `tooling/tests/` is fixture *content*, and
no test writes to a real project (T3 is read-only there; mutations sandbox by construction).

| Tier | What it checks | Typical single-tier run |
|---|---|---|
| **T0** static | `bash -n` every script + the harness; `--help` on the 14 automation scripts; forbidden-idiom greps (`declare -A`, `\| xargs`, `grep -c … \|\| echo 0`, whole-file `verify-failed` greps, bare `## Tasks` anchors, `exec/bash "$0"` respawns) | ~30 s |
| **T1** unit | per-script cases in `tests/cases/*.t.sh` (happy + negative + idempotency) against F1 scaffold / F2 mid-lifecycle / F3 hostile fixtures, plus the two-owner MR-URL parity case and `pw-lib`/`pw-status` selftests invoked from a foreign cwd | ~2 min |
| **T2** battery | golden matrices `expectations/battery.tsv` + `gates.tsv`: every read-only invocation and every preflight gate on every fixture, rc pinned, **`→ fix:` remediation asserted on every non-zero**, script-crash detector, and a **mode-completeness** rule (every advertised mode appears in a pinned row) | ~2 min |
| **T3** corpus | read-only battery over real projects when `--corpus-dir DIR` (or `PW_CORPUS_DIR`) is given; crash-vs-clean-failure classification with `→ fix:` contract; pre-baseline projects are clean failures advising "refresh local templates"; a current-baseline project is the golden gate; personal data issues waived via `~/.pw/test-issues.tsv` | opt-in |
| **T4** consistency | `pw-doctor` synced (run with the fixture env stripped; regen is `pw-doctor --fix` — never edit installed provider copies), registry symmetry (14 files ⇄ index ⇄ command/agent/skill wiring, allowlist `expectations/unwired.ok`), info-boundary greps, doctrine canaries (sources-only rule, FIELD-BULLET rule, phase-machine token line) | ~20 s |

`pw-doctor.sh --test` delegates to `pw_test.sh` (default tiers).

## Cadence — how long, and how often

The default run (~3–4 min) is the **commit gate**, not the edit-loop gate. Inside an edit loop
run the cheap slice first: `--tier T0` (~30 s) catches syntax + every idiom that ever bit us, and
`--tier T1 --only <script>` (~20 s) covers the script you touched; promote to the full run once
before committing. Tier costs are fixtures-once (built per invocation, ~15 s), so a filtered run
is genuinely fast.

`--mutation` is a **meta**-test of the suite itself (~20 min for all 25 rows — one fresh-suite
child per row). It never belongs in a per-edit loop; run it when the harness, expectations, or
the coupling register changed, or per-register-slice with a filter (see below).

## The meta-test (`--mutation`)

`expectations/mutations.tsv` reverts one **documented fix** per coupling-register row (C1–C24, plan 16 §5) in a working-tree copy and asserts the harness catches it: a mutation that passes =
a vacuous test — the exact failure mode that produced this protocol. Each row:
`id \t file(rel tooling/) \t OLD \t NEW \t tier \t only`; a drift-flagged row means the anchor
moved with the code — re-pin it, don't delete it. After adding any nontrivial fix, add a row for
its coupling and verify the one anchor: `--mutation <id>` (~1 min/row) or a slice like
`--mutation 'C(1[7-9]|2[0-3])-'`.

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
