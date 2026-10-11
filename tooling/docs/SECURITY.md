# Security doctrine — untrusted input, sink gates, write hygiene

Audience: **maintainers** changing the bundle. The threat model, the boundary table, and the
rules every change must satisfy. The enforcement floor is mechanical: `tooling/tests/static.sh`
(forbidden idioms) + `tooling/tests/cases/pw-security.t.sh` (behavioral refusals) + the
C-register in `expectations/mutations.tsv` (every guard reverts to a failing test).

## Threat model

- **Untrusted input:** anything an AI agent writes into a project directory — task-file fields
  (`Branch`, `Repo:`, `Worktree:`, `Stacked on:`, `Execute with:`, MR URLs, free-text notes),
  PLAN cells, README dashboard rows, review files, prepared-packet manifests, file names under
  `analysis/`/`task/`. Content pasted into `context/` from issues or the web is the carrier.
  CLI flag values composed by the orchestrating agent are the same trust tier.
- **Trusted by design:** `pw.config.sh` (sourced as code — the extension mechanism), the bundle's
  own scripts, operator install paths.
- **Local attacker position:** any process running as the same user (every spawned agent, every
  worktree build) can plant files and symlinks inside project directories.
- **Not in scope:** provider CLI internals, model behavior, forge-side trust.

## Boundary table — which validator guards which input

| Input | Validator | Where enforced |
|---|---|---|
| Project slug | `pw_proj_slug_ok` (one component) + `pw_proj_dir` (physical containment) | one shared `proj_dir` per entity |
| Task id (CLI or field) | `pw_task_id_ok` (anchored `^T0n$`) | every CLI parse + `pw_stack_parent` |
| Branch / base (git use) | `pw_branch_ok` (ref charset, no leading dash) | before every push / worktree-add / ref |
| Repo / worktree path | `pw_dir_within` (physical, symlink-final refused) | before every `git -C` / `cd` target |
| Provider token → var name | charset gate (`*[!A-Za-z0-9_-]*` → refuse) | `cmd_model_check`, `pw_api_entries` sinks |
| Markdown value → row/cell/line writer | reserved-char gate (`_stack_val_bad` class: `\|`, TAB, NL, backslash) or `pw_meta_check` | every awk `-v` writer |
| Values in sed/perl/awk **program** text | never — use bash replacement (``${var//pat/repl}``) or `awk -v` data | static idiom table |
| Staged file writes | `pw_tmpfile` + `mv` (mktemp-backed) | every markdown/state writer |
| Symlinks on read | refuse (lane walk, `[ -L ] && skip`) | review lanes, blockers |
| Symlinks on write | unlink-before-write or mktemp target | generators, staging |
| Install dirs from provider hooks | `pw_hook_dir_ok` (non-empty absolute) | pw-doctor, offboard |
| Provider env files | shell-special-char refusal (`"` `` ` `` `$` `\`, newline) | bootstrap, pw-doctor rewrite |

## Rules

1. **Gates live in the SINK, not the caller.** A new flag/parser/writer validates its own input
   even if every current caller already did. Call-site-only checking is what made ~29 findings
   possible; safe-by-caller is one refactor away from exposure.
2. **No data in program strings.** A shell variable never becomes sed/perl/awk program text.
   Token stamping uses `pw_stamp_tokens`/bash replacement; regex matches pass data via `-v` and
   compare fields. The static table bans the shapes (`s/<PROJECT_NAME>/`, `\Q{{PW_HOME}}\E`,
   `'"$`, `pw_phase_hint | sed`).
3. **Every staged write goes through `pw_tmpfile` + `mv`.** No fixed `.tmp`/`.dash-err`/
   `.pwrev.$$`/`.pwtmp.$$` names, no PID fallbacks: mktemp failure dies with a fix hint
   (`pw_tmpfile`'s single internal fallback excepted). Concurrent writers and planted symlinks
   both need unique, pre-created targets.
4. **Symlink discipline.** Reads: refuse to follow (lane policy). Writes: unlink a stale link
   before redirecting, or write to a mktemp target. `rm -rf` on a symlink removes the link only —
   never build an `rm` operand from unchecked input, and require physical containment
   (`pw_path_within`/`pw_dir_within`) before `git -C`/`cd`/`rm` on task-file-derived paths.
5. **Row-integrity before emission.** Anything re-emitted through `awk -v` (backslash-escape
   processing!) or spliced into a table cell rejects `|`, TAB, newline, and backslash sequences.
   Forgeable markers (`<!-- pw-…-comment: -->`) are built from charset-gated ids only.
6. **New input surface ⇒ validator + test + mutation row.** A new flag, operator, parser, write
   path, subprocess, or program string ships with: a sink gate, a `pw-security.t.sh` (or entity
   case) check proving refusal, and a mutation row that bites when the gate is removed. A change
   without its catcher is a review blocker.
7. **Cross-check external references.** An MR URL from a task file never chooses the host or
   repo of a credential-bearing forge call by itself — the repo's own `origin` is the pin and
   the URL host is only a cross-check (`monitor`, `_stack_mr_view`, pw-context adopt).

## Accepted residuals (do not "fix" silently)

- `bash -c "$vcmd"` Verify execution is the product's trust decision (owner-accepted): the human
  breakdown gate is the review those commands get. Aggravators are bounded: workdir containment,
  `--evidence-dir` mkdir fails loudly. Doctrine side lives with prompt-injection boundaries.
- `pw.config.sh`-sourced idioms (provider names, install paths) are below the trust boundary;
  they still get the same sink gates where cheap, but a config that executes code is by design.
- offboard/doctor leave unmarked `pw-*` orphans in place (reported + skipped). The bundle
  marker (`<!-- pw-generated: … -->`) is appended by gen-commands/gen-agents; only marked
  residue is removed. Pre-marker residue needs one hand cleanup after an upgrade.
- The mdlib standalone fallback duplicates `pw_tmpfile`; keep the two definitions in sync.
