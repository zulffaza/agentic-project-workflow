# AGENTS.md — tooling entry point for MAINTAINERS of the bundle

**Audience:** you (an AI agent, or a human) about to **change** anything under `tooling/`,
`template/`, or the provider surfaces — scripts, canonical commands, agents, skill sources,
generators, docs policy, the test harness. This is the *internal* surface: implementation detail
lives here deliberately. Users driving projects through `/pw-*` never need this file; the
bundle-root [`../AGENTS.md`](../AGENTS.md) covers them.

> **Cheat-sheet first:** [`skill-internal/pw-maintainer/SKILL.md`](./skill-internal/pw-maintainer/SKILL.md)
> is the navigational front door over everything below — the change/test loop, the placement
> conventions, and the doc boundary, one reference at a time. Maintainer-only; **not**
> provider-installed (it lives outside the generated `skill/` set).

Start here, in order: the doctrine below, then the change protocol
([`docs/testing.md`](./docs/testing.md)), then a script's usage contract
([`docs/scripts/README.md`](./docs/scripts/README.md)). Adding a script, command, or operator?
Read [`docs/conventions.md`](./docs/conventions.md) first — it answers "where does this go?"
(S-rules: one script per entity — with S1a artifact-family granularity and S1b facets for
the second-level split; L-rules: everything under `scripts/{entities,lib,toolchain}/` decided by
the toolchain test; C-rules: one command per entity + operators; A-rules: free-text args).

## Doctrine: sources only (canary-tested)

`tooling/` and `template/` are the single source of truth; installed provider copies are
generated: `pw-doctor.sh --fix` regenerates them. Never hand-edit `~/.claude`, `~/.cursor`,
or `~/.config/kilo` command/agent/skill surfaces — a regen destroys anything that lived only
there (this has actually happened; the rule is a canary-tested doctrine). A fix applied to live
copies must be **moved into the sources before regenerating**, or the regen silently destroys it.
If you maintain a shipped skill's canonical copy elsewhere (e.g. a personal hub dir), refresh the
bundle copy under `skill/<name>/SKILL.md` before committing/sharing — the bundle copy is the source
the installer links (moved here from the human onboarding guide 2026-09-25).

State mutations inside any project go through the entity scripts — `pw-status.sh`
(`log|status|oneliner|adopted|phase|dashboard-task-status|task-accept`), `pw-review.sh`
(`init|gate|reopen|auto-signoff|has-open|count|reindex|archive|…`), `pw-context.sh`
(`adopt|add-input|add-repo|fetch|…`), `pw-config.sh` (`ai-review|ai-model|model-check`) —
never hand-edits of load-bearing lines, and `pw_field`/`pw_plan_pairs`/`_pw_url_from_line`/
`pw_trim` in `pw-common.sh` are the reader plumbing commands rely on. New shared logic: add to
the libraries, don't re-implement in a caller (P2). The old frozen legacy core (`pw-lib.sh`) is
**fully dissolved** (S2 endgame): new capability goes to the entity's own script, shared
document primitives to `pw-mdlib.sh` (source-only library: comment-blanking, review-item
detection, sign-off reads, table splices, dashboard-cell edits), project-state primitives to
`pw-common.sh` — see [`docs/conventions.md`](./docs/conventions.md).

## What lives where (implementation map)

```
tooling/
├── README.md            ← human maintainer guide (this file is the agent-facing sibling)
├── pw.config.example.sh ← config schema (the live pw.config.sh lives at the bundle root)
├── scaffold.sh · gen-commands.sh · gen-agents.sh   ← generators (template → project; sources → providers)
├── scripts/lib/pw-common.sh (shared plumbing) · scripts/toolchain/pw-doctor.sh (sync + --fix + --test)
├── automation scripts (pw-status … pw-context)  ← usage: docs/scripts/ (index + groups); registry: tests/static.sh
├── pw-worktree.sh teardown       ← safe worktree removal at close-out (refuses CWD/dirty trees)
├── commands/ · agents/ · skill/           ← canonical sources (provider-neutral; tokens {{PW_HOME}} …)
├── skill-internal/pw-maintainer/          ← maintainer cheat-sheet skill — read-as-file, NOT provider-installed (outside the skill/ glob)
├── docs/                                  ← registries/policy docs the AGENTS read
│   ├── scripts/                           ← script usage contracts (exit codes, → fix: lines)
│   └── testing.md · forges.md · rfc.md · rfc-backends.md · providers.md · memory.md
└── tests/                                 ← the change-testing harness (see docs/testing.md)
    ├── pw_test.sh (runner) · pw_test_lib.sh · static.sh · battery.sh · corpus.sh · mutate.sh
    ├── cases/*.t.sh · selftest_entry.sh · bin/{glab,gh} (offline forge shims)
    └── expectations/{battery,gates,mutations}.tsv · unwired.ok   ← pins/meta-register
template/          ← scaffold source (FIELD-BULLET RULE banner = machine fields are value-only)
```

The **T0/T4** checks exist because each banned pattern is a bug that shipped once — do not
"clean up" a grep, an anti-idiom rule, or an `expectations/*.tsv` pin without reading
`docs/testing.md` first (T2 pins are current behavior, not law — re-pin deliberately via
`--capture battery|gates|both` and review the diff).

## After ANY change under tooling/ or template/

`bash tooling/tests/pw_test.sh` (default tiers T0,T1,T2,T4 — the commit gate; while editing use
`--tier T0` ~2 s, `--tier T4` ~6 s, or `--tier T1 --only <script>` — fixtures build only when the
selected tiers consume them). `pw-doctor.sh --test` delegates here.
Changed behavior of a documented format/contract → add a coupling row to
`tooling/tests/expectations/mutations.tsv` (revert of the fix) and prove it bites:
`pw_test.sh --mutation <id>` (~5 s/row with a warm cache). During development sweep only the
rows for files you touched (`--mutation 'C2[5-9]'`); the full `--mutation all` belongs at the
ship gate (~1 min, parallel — each row mutates a disposable bundle copy, never your tree).
Before editing anything under `tests/` or authoring a register row, read
[`docs/testing.md`](./docs/testing.md) §Inside the harness (fixture scan/materialize flow, cache
recipe rule, watchdog, fixture-pollution etiquette: clone `$F2`, never mutate it) and
§Writing a mutation row. Change type → minimum tiers: the table in
[`docs/testing.md`](./docs/testing.md). Re-run `pw-doctor.sh` (expect **All synced**) after any
`commands/`/`agents/`/`skill/`/`template/` edit — it compares generated-vs-installed.

## Information boundary (what users must never learn here)

- User-facing docs live at the bundle root `docs/` + `../README.md` + `../AGENTS.md` — they describe
  behavior, never mechanics: the automation scripts (tooling/tests/static.sh registry) must not be
  named there (T4 greps; the one
  allowed human reference is the `pw-env.sh`/`pw-doctor.sh`-level convenience and the entity scripts for
  state edits where docs/REVIEW.md already names it).
- Internal plan numbers / session history never appear in shipped files (T4 greps).
- T3 corpus results: never commit real project slugs; waivers stay in `~/.pw/test-issues.tsv`.

Human maintainer guide: [`README.md`](./README.md). Testing protocol: [`docs/testing.md`](./docs/testing.md).
Script-by-script usage: [`docs/scripts/README.md`](./docs/scripts/README.md).
