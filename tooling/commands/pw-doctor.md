---
description: Check health — installed commands + skill vs the bundle (global side), or one project's docs/config/gates consistency (--project <slug>); --fix repairs what has a deterministic writer
args: [--fix | --project <slug> [--fix]]
---
Arguments: {{ARGS}}.

`/pw-doctor` has two sides with the same "validate, print ✓/✗ + fix, repair on `--fix`" idiom,
but different scopes:

## Global side (no `--project`) — health of the install everything else rides on

Run the project-workflow sync check and show its output:
```bash
{{PW_HOME}}/tooling/scripts/toolchain/pw-doctor.sh {{ARGS}}
```
It verifies, per enabled provider (from `pw.config.sh`), that the installed `project-workflow`
skill and the generated `/pw-*` command files match what this bundle would produce now — catching a
moved/renamed bundle, edited command sources, or a stale skill.

- If everything is in sync, say so and stop.
- If anything is out of sync and `--fix` was **not** passed, summarize exactly what drifted (which
  provider, skill vs commands) and tell me to re-run `/pw-doctor --fix` (or `{{PW_HOME}}/bootstrap.sh`).
- If `--fix` was passed, report what it repaired and confirm the re-check is clean.

## Project side (`--project <slug>`) — is THIS project operated well

```bash
{{PW_HOME}}/tooling/scripts/toolchain/pw-doctor.sh --project <slug> [--fix]
```
(behind it: the deterministic project walk in `tooling/scripts/entities/pw-project-doctor.sh`).
The report is grouped into 8 human-labelled sections — Documentation & template lint, RFC data
(optional side-loop: findings are `·` warnings while the project hasn't engaged RFC — once a
target/push/publication exists there, they are real ✗ like any other check), Plan (rows +
dependencies), Configuration, Provider & model pins (an ✗ means a live task's pin is unusable
against the current config; "ran with a different model than the pin" is history-vs-intent and
stays a `·` — re-pinning is the user's free choice), Execution health (stale runs + status-aware
worktrees/branches: an accepted task's torn-down worktree is expected), Review gates, and
Merge requests ↔ task status (read from the dashboard MR table the flows maintain — no live
forge call). Absence of a config line is a defect (`off`/`—` are values); everything is checked
against `pw.config.sh` as it is today, so a provider dropped mid-project lights up.

Present the ✓/✗/· report as-is (· lines are informational and never fail). Then:
- On any ✗ without `--fix`: list each one with its `→ fix:` line. Do not repair anything yourself —
  the script is the writer.
- With `--fix`: only repairs that have a deterministic writer are applied (config lines ensured
  with explicit defaults; unexpanded scaffold tokens in task files stamped); everything else keeps
  printing its fix command. Report what changed and re-run the check to confirm.

Per-project *configuration values* (not this check) live on `/pw-config`.

Never hand-edit the generated command files — regeneration via the script is the fix.
