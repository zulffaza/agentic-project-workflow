# Status and pre-flight scripts

The three scripts you call **before** anything expensive: get a picture (`pw-status.sh`), check
the gates (`pw-preflight.sh`), and see where reviews stand (`pw-review-scan.sh`). All three are
read-only — they never modify a project.

## pw-status.sh

One deterministic project-status report, in place of an agent reading five files by hand.

```bash
$PW_HOME/tooling/pw-status.sh <slug>                  # full report
$PW_HOME/tooling/pw-status.sh <slug> --skip-cli-check # omit the forge/CLI auth section
$PW_HOME/tooling/pw-status.sh --selftest              # isolated temp-project smoke test
```

**Output** — markdown sections, in this fixed order; feed it to the user as-is:

```
## Phase: executing
## Tasks                      ← README.md task table, verbatim
## PLAN                       ← task/PLAN.md task table (omitted if no PLAN.md)
## Unresolved review items     ← "  - <file> (N open)" lines, or "  (none)"
## AI Review modes            ← analysis/plan/task-plan/task-exec/ship modes
## Recent activity            ← last 5 LOG.md lines
## Blockers                   ← heuristic list (unapproved gates, open items, verify-failed)
## Next action                ← the one command the phase currently suggests
## CLI auth status            ← ✓/✗ one line per forge CLI (skipped with --skip-cli-check)
```

**Reading failures:** exit `2` + `pw-status: no such project …` on stderr. `## Blockers: (none)`
does *not* mean pre-flight will pass — blockers are heuristic; preflight is authoritative.

**When to use:** `/pw-status` report mode; any agent that wants a status snapshot without
re-implementing the file reads. Drop the CLI-auth section (`--skip-cli-check`) when calling it
from scripts that run frequently.

## pw-preflight.sh

Checks **all** gates for one command and fails fast — run it before invoking the phase agent.

```bash
$PW_HOME/tooling/pw-preflight.sh execute      <slug>   # PLAN approved, phase valid, scope/model resolvable
$PW_HOME/tooling/pw-preflight.sh breakdown    <slug>   # analysis reviews approved, RFC open items resolved
$PW_HOME/tooling/pw-preflight.sh ship         <slug>   # shippable tasks exist, verify passed
$PW_HOME/tooling/pw-preflight.sh close        <slug>   # all tasks accepted
$PW_HOME/tooling/pw-preflight.sh review <slug> [phase] # review files exist for phase: analysis|plan|task-plan|task-exec
```

**Output:** silent on success (exit `0`). On failure, exit `1` with one `pw-preflight: …` line —
it names the gate *and* the fix, e.g.:

```
pw-preflight: PLAN review gate not approved (run /pw-review to approve)
```

**Reading failures:** every message is terminal for that command — do the named action, re-run.
Unknown command argument → usage line, also exit 1.

**When to use:** first step of `/pw-execute`, `/pw-breakdown`, `/pw-ship`, `/pw-close`,
`/pw-review`. Any agent invoked *without* a command re-runs the same pre-flight itself.

## pw-review-scan.sh

Structured summary of every review file's item counts and sign-off state.

```bash
$PW_HOME/tooling/pw-review-scan.sh <slug>                  # all review files
$PW_HOME/tooling/pw-review-scan.sh <slug> --phase analysis # or: plan | task-plan | task-exec
```

**Output** — one line per review file, fields present only when non-zero:

```
analysis/topic.review.md: 2 open, 3 resolved, 1 pending question(s)
task/review/PLAN.review.md: 5 resolved (approved)
task/review/T03.review.md: 1 open (in-review)
```

Trailing `(approved|in-review|changes-requested)` is the **last row of the file's Sign-off
table**. `No review files found` + exit `0` is a valid empty state (project too early for reviews).

**Reading failures:** exit `2` = usage error or missing project (`pw-review-scan: …` on stderr).

**When to use:** instead of grepping `review/` yourself — `pw-status.sh` and `/pw-review`,
`/pw-close` pre-flights all call it. Filter with `--phase` when you only care about one lane.
