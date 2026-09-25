# Change protocol — the ordered loop

Canonical statement: [`tooling/AGENTS.md`](../../../AGENTS.md) §"After ANY change under tooling/ or
template/"; test detail: [`tooling/docs/testing.md`](../../../docs/testing.md). This page is the route,
not a restatement — open the doc for the load-bearing wording.

1. **Edit the source** under `tooling/` (or `template/`) — never a generated provider copy. If you
   fixed a live copy under `~/.claude` / `~/.cursor` / `~/.config/kilo`, move the fix into the
   source first, then regenerate (sources-only doctrine).
2. **Run the harness.** `bash tooling/tests/pw_test.sh` is the commit gate (default tiers
   T0,T1,T2,T4). While editing, narrow it: `--tier T0` (~2 s canaries), `--tier T4` (~6 s doctrine
   canaries), or `--tier T1 --only <script>` (one script's selftests). Fixtures build only when the
   selected tiers consume them. `pw-doctor.sh --test` delegates here.
3. **Changed a documented format or contract?** Add a coupling row to
   `tooling/tests/expectations/mutations.tsv` (the revert of your fix) and prove it bites:
   `pw_test.sh --mutation <id>` (~5 s/row with a warm cache). During development sweep only the rows
   for files you touched (`--mutation 'C2[5-9]'`); the full `--mutation all` (~1 min, parallel, each
   row mutates a disposable bundle copy) belongs at the ship gate. Authoring rules →
   [`testing.md`](../../../docs/testing.md) §"Writing a mutation row". Check the register's "Next free"
   ID against draft-plan reservations before minting.
4. **Sync the generators.** After any `commands/` / `agents/` / `skill/` / `template/` edit, run
   `tooling/scripts/toolchain/pw-doctor.sh` and expect **All synced**; `--fix` regenerates drifted
   provider copies from source. (`skill-internal/` — where this skill lives — is not generated and
   not doctor-checked.)
5. **Version / release.** Once the bundle carries a `VERSION` file + changelog (a separate
   versioning initiative), the release step classifies the semver bump and stages the changelog
   entry; until then, changes land on `main` under the owner's commit approval. **Commit and push
   are always the human gate** — no script does either.

**Minimum tiers by change type:** the table in [`testing.md`](../../../docs/testing.md) §"The agent
protocol (change type → minimum tiers)". Before editing anything under `tests/`, read
[`testing.md`](../../../docs/testing.md) §"Inside the harness" (fixture scan/materialize flow, the
cache recipe rule, the watchdog, and fixture-pollution etiquette: **clone `$F2`, never mutate it**).
