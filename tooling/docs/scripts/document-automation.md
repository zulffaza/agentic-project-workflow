# Document automation scripts

Validate structure (`pw-doc.sh lint`), extract summaries (`pw-doc.sh summary`), or reconcile
drifted docs (`pw-doc.sh sync`).

## pw-doc.sh lint

Checks the format conventions the pipeline depends on — run before breakdown/execute/ship/close
so convention violations surface as cheap errors, not as agent confusion later.

```bash
$PW_HOME/tooling/scripts/entities/pw-doc.sh lint analysis  <slug> <topic|--all>  # analysis/<topic>.md
$PW_HOME/tooling/scripts/entities/pw-doc.sh lint task     <slug> <task-id|--all> # task/T0n.md
$PW_HOME/tooling/scripts/entities/pw-doc.sh lint plan     <slug>                 # task/PLAN.md
$PW_HOME/tooling/scripts/entities/pw-doc.sh lint review   <slug> <path>          # a .review.md file
$PW_HOME/tooling/scripts/entities/pw-doc.sh lint dashboard <slug>                # README.md tables
$PW_HOME/tooling/scripts/entities/pw-doc.sh lint all      <slug>                 # everything the project has
```

**What each mode checks (so you know what "lint failed" implies):**

- `analysis` — sections §1 Problem … §5 Decisions present.
- `task` — required fields (`Repo:`, `Base branch:`, `Branch:`, `Execute with:`, `Story
  points:`) and required sections (`## Steps`, `## Verify`, `## Result`). Optional fields —
  `Route:` (`auto|subagent|headless`), `Effort:`, `Thinking:` — are read by the routing ladder
  but never linted; absent = `auto`/provider default, so old task files keep passing.
- `plan` — task table (template heading `## Task table`, also accepts `## Tasks`) has the
  Task/Repo/Branch/SP/Execute with columns.
- `review` — review-file structure (Items / Open questions / Sign-off).
- `dashboard` — README task-table row count matches the actual task files.
- `all` — every analysis doc, PLAN, `T*.md` task file, both review dirs, and the dashboard.

**Output:** silent, exit `0` on pass. On fail, exit `1` with a complete list:

```
pw-doc lint: found 2 error(s):
  - …/task/T01-foo.md: missing 'Repo' field (as '- **Repo:**' bullet or '^Repo:' line)
      → fix: add '- **Repo:** <value>' in the header bullets — value must agree with the task's PLAN row
  - …/task/T01-foo.md: missing '## Verify' section
      → fix: see …/task/_TEMPLATE-task.md for the required sections
```

It collects **all** errors before exiting — fix everything in one pass, re-run to confirm.
Most errors carry a `→ fix:` remediation line naming the concrete next action (a template to
copy from, the command to run); relay it verbatim rather than guessing at a repair.

**Reading failures:** a `not found` error (missing doc file) is exit 1 + `pw-doc lint: …` too —
that means the artifact doesn't exist yet, i.e. the phase hasn't produced it. A missing `analysis`
doc while linting `--all` only happens if the dir was empty (reported as "`--all matched none`").

## pw-doc.sh summary

Cheap digests instead of full-file reads when an agent only needs the headlines.

```bash
$PW_HOME/tooling/scripts/entities/pw-doc.sh summary analysis <slug> <topic>  # §1 problem + chosen approach + repos
$PW_HOME/tooling/scripts/entities/pw-doc.sh summary task    <slug> <task-id> # Repo + Branch + goal one-liner
$PW_HOME/tooling/scripts/entities/pw-doc.sh summary plan    <slug>           # task count, ΣSP, repos, produced-by
$PW_HOME/tooling/scripts/entities/pw-doc.sh summary project <slug>           # one-liner, phase, task status counts
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

## pw-doc.sh sync

Re-derives every derived document from on-disk truth (task files + PLAN) — the repair tool when
`pw-doc.sh lint dashboard` or `pw-doctor.sh` reports drift.

```bash
$PW_HOME/tooling/scripts/entities/pw-doc.sh sync <slug>                 # dashboard + PLAN + task docs
$PW_HOME/tooling/scripts/entities/pw-doc.sh sync <slug> --dashboard-only # or: --plan-only | --tasks-only
```

**Output:** progress lines only:

```
Syncing dashboard (README.md)...
Dashboard sync complete
```

Missing inputs are skipped with a message (`PLAN.md not found, skipping`), not fatal.

**When to use:** after manual/agent edits that updated a task file but not the README or PLAN;
before `/pw-close` if dashboard lint failed. **Writes files** — unlike the two linting/summarizing
scripts above, run it deliberately, and re-lint after (`pw-doc.sh lint all <slug>`).
