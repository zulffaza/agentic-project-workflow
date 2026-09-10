# Document automation scripts

Validate structure (`pw-doc-lint.sh`), extract summaries (`pw-doc-summary.sh`), or reconcile
drifted docs (`pw-doc-sync.sh`).

## pw-doc-lint.sh

Checks the format conventions the pipeline depends on — run before breakdown/execute/ship/close
so convention violations surface as cheap errors, not as agent confusion later.

```bash
$PW_HOME/tooling/pw-doc-lint.sh analysis  <slug> <topic|--all>  # analysis/<topic>.md
$PW_HOME/tooling/pw-doc-lint.sh task     <slug> <task-id|--all> # task/T0n.md
$PW_HOME/tooling/pw-doc-lint.sh plan     <slug>                 # task/PLAN.md
$PW_HOME/tooling/pw-doc-lint.sh review   <slug> <path>          # a .review.md file
$PW_HOME/tooling/pw-doc-lint.sh dashboard <slug>                # README.md tables
$PW_HOME/tooling/pw-doc-lint.sh all      <slug>                 # everything the project has
```

**What each mode checks (so you know what "lint failed" implies):**

- `analysis` — sections §1 Problem … §5 Decisions present.
- `task` — required fields (`Repo:`, `Base branch:`, `Branch:`, `Execute with:`, `Story
  points:`) and required sections (`## Steps`, `## Verify`, `## Result`).
- `plan` — task table (template heading `## Task table`, also accepts `## Tasks`) has the
  Task/Repo/Branch/SP/Execute with columns.
- `review` — review-file structure (Items / Open questions / Sign-off).
- `dashboard` — README task-table row count matches the actual task files.
- `all` — every analysis doc, PLAN, `T*.md` task file, both review dirs, and the dashboard.

**Output:** silent, exit `0` on pass. On fail, exit `1` with a complete list:

```
pw-doc-lint: found 8 error(s):
  - …/task/T01-foo.md: missing 'Repo:' field
  - …/task/T01-foo.md: missing '## Verify' section
```

It collects **all** errors before exiting — fix everything in one pass, re-run to confirm.

**Reading failures:** a `not found` error (missing doc file) is exit 1 + `pw-doc-lint: …` too —
that means the artifact doesn't exist yet, i.e. the phase hasn't produced it. A missing `analysis`
doc while linting `--all` only happens if the dir was empty (reported as "`--all matched none`").

## pw-doc-summary.sh

Cheap digests instead of full-file reads when an agent only needs the headlines.

```bash
$PW_HOME/tooling/pw-doc-summary.sh analysis <slug> <topic>  # §1 problem + chosen approach + repos
$PW_HOME/tooling/pw-doc-summary.sh task    <slug> <task-id> # Repo + Branch + goal one-liner
$PW_HOME/tooling/pw-doc-summary.sh plan    <slug>           # task count, ΣSP, repos, produced-by
$PW_HOME/tooling/pw-doc-summary.sh project <slug>           # one-liner, phase, task status counts
```

**Output** — `Key: value` lines, e.g.:

```
Tasks: 6 (ΣSP=23)
Repos: api-service,worker-service
Produced by: /pw-breakdown 2026-09-02
```
```
One-liner: migrate payments retry queue
Phase: executing
Tasks: 1 todo, 2 in-progress, 3 done, 0 accepted
```

Fields that can't be found print `(not set)` — that's a doc problem to fix with the writer
command, not a script failure. Exit `2` only for usage errors / missing project or doc file.

## pw-doc-sync.sh

Re-derives every derived document from on-disk truth (task files + PLAN) — the repair tool when
`pw-doc-lint.sh dashboard` or `pw-doctor.sh` reports drift.

```bash
$PW_HOME/tooling/pw-doc-sync.sh <slug>                 # dashboard + PLAN + task docs
$PW_HOME/tooling/pw-doc-sync.sh <slug> --dashboard-only # or: --plan-only | --tasks-only
```

**Output:** progress lines only:

```
Syncing dashboard (README.md)...
Dashboard sync complete
```

Missing inputs are skipped with a message (`PLAN.md not found, skipping`), not fatal.

**When to use:** after manual/agent edits that updated a task file but not the README or PLAN;
before `/pw-close` if dashboard lint failed. **Writes files** — unlike the two linting/summarizing
scripts above, run it deliberately, and re-lint after (`pw-doc-lint.sh all <slug>`).
