# Testing harness — tiers, fixtures, mutation rows

Canonical: [`tooling/docs/testing.md`](../../../docs/testing.md). Runner: `tooling/tests/pw_test.sh`.
This page routes; the doc owns the detail.

**Tiers** (what each proves):
- **T0** — canaries: syntax, usage-header presence, forbidden-idiom greps (~2 s).
- **T1** — per-script selftests (each entity's own cases under `tests/cases/*.t.sh`).
- **T2** — fixture integration (the battery against materialized projects).
- **T3** — real-project corpus (never commit real slugs; waivers live in `~/.pw/test-issues.tsv`).
- **T4** — doctrine canaries (the consistency + boundary greps in `tests/static.sh`).

**Cadence and which tiers** → [`testing.md`](../../../docs/testing.md) §"Cadence" and §"The agent
protocol (change type → minimum tiers)". The default `pw_test.sh` run is T0,T1,T2,T4 — the commit
gate. Narrow while editing with `--tier T0` / `--tier T4` / `--tier T1 --only <script>`.

**Before editing `tests/` or writing a mutation row** → read
[`testing.md`](../../../docs/testing.md) §"Inside the harness": the fixture scan/materialize flow, the
cache **recipe rule**, the watchdog, and fixture-pollution etiquette (**clone `$F2`, never mutate
it**).

**Mutation rows** — the meta-test, run with `pw_test.sh --mutation <id>` →
[`testing.md`](../../../docs/testing.md) §"Writing a mutation row". The register is
`tooling/tests/expectations/mutations.tsv`. Rules that bite:
- the OLD string must be **byte-exact and unique** in its target file;
- the catcher must **not** depend on the mutation changing fixture bytes (the recipe-hash cache keys
  on fixture content, so a byte-changing mutation can silently skip the rebuild);
- **check the "Next free" ID against draft-plan reservations** before minting a new one.

**Re-pinning** T2 battery/gates is deliberate, never incidental: `--capture battery|gates|both`,
then review the diff — T2 pins capture *current* behavior, not law. Sweep only the rows for files
you touched during development (`--mutation 'C2[5-9]'`); run the full `--mutation all` at the ship
gate.
