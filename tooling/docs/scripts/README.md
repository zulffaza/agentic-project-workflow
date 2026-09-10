# Automation script reference

**Audience:** operators and agents running the workflow. This is *usage* documentation — what to
call, how to read the output, what to do when it fails. Script internals are in the scripts
themselves; nobody needs them to use these.

The 14 scripts in `tooling/` handle the deterministic parts of the pipeline — status reporting,
gate checking, document validation/summaries, ship mechanics, URL fetching — so an agent doesn't
spend tokens re-reading files it could just query. The rule they all serve: **script the
mechanical, keep the agent for the creative.**

## Index

| Group | Scripts | Use when |
|---|---|---|
| [Status and pre-flight](./status-and-preflight.md) | `pw-status.sh` `pw-preflight.sh` `pw-review-scan.sh` | Getting an overview, or before any expensive agent invocation |
| [Document automation](./document-automation.md) | `pw-doc-lint.sh` `pw-doc-summary.sh` `pw-doc-sync.sh` | Validating structure, extracting summaries, reconciling drifted docs |
| [Ship and sync](./ship-and-sync.md) | `pw-ship-resolve.sh` `pw-ship-exec.sh` `pw-mr-state-batch.sh` `pw-pipeline-monitor.sh` | Running `/pw-ship`, waiting on CI, checking MR states in bulk |
| [Workflow automation](./workflow-automation.md) | `pw-rfc-comments.sh` `pw-context-fetch.sh` `pw-adopt-snapshot.sh` `pw-worktree-create.sh` | RFC comment loops, analysis context fetch, adoption, worktree creation |

## Common invocation pattern

```bash
$PW_HOME/tooling/<script>.sh <args> [options]      # shell
{{PW_HOME}}/tooling/<script>.sh <args> [options]   # inside command/agent/skill prompt files
```

- `-h` / `--help` prints the script's own usage header and exits 0 — on every script.
- Human-readable errors go to **stderr**, prefixed with the script name (`pw-preflight: …`,
  `pw-doc-lint: …`). On success most scripts are silent or print a short report to stdout.
- The project slug resolves under `$PW_PROJECTS_DIR` (default: the bundle's parent-of-parent);
  a missing project is always an error, never an empty success. Scripts that touch repos resolve
  them under `PW_REPOS` the same way.
- Selftests exist on `pw-status.sh --selftest` (and the suite's spine, `pw-lib.sh selftest`);
  run those after editing tooling.

## Exit codes — read this before "handling" a failure

| Exit | Meaning | Applies to |
|---|---|---|
| `0` | success (or, for `pw-review-scan.sh`, "nothing to report") | all |
| `1` | the check **failed** — error lines on stderr say what is wrong | `pw-preflight.sh`, `pw-doc-lint.sh`, `pw-pipeline-monitor.sh` (pipeline failed) |
| `2` | bad usage, missing project, or (for `pw-pipeline-monitor.sh`) timeout | everything else; `pw-pipeline-monitor.sh` shares `2` between usage errors and timeouts — read the message |
| `0`/`1` | `pw-status.sh` uses `2` for missing-project/usage errors, `1` never | `pw-status.sh` |

**On any non-zero exit: stop and report or fix the stderr message — do not proceed and hope.**
That is the whole contract commands rely on: pre-flight fails *before* agent tokens are spent.

## Success checklist for a failing invocation

1. Read the stderr prefix — it names the script and usually the missing gate or file.
2. "not approved / open items" → run the review it names (e.g. `/pw-review <slug> plan`).
3. "not found" → the phase you're in hasn't produced that artifact yet; run the upstream command.
4. Exit `2` from `pw-pipeline-monitor.sh` with "still running" → CI hasn't settled; re-run or
   raise `--timeout`.
