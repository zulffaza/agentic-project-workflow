# Status and pre-flight scripts

The three scripts you call **before** anything expensive: get a picture (`pw-status.sh`), check
the gates (`pw-preflight.sh`), and see where reviews stand (`pw-review.sh scan`). All three are
read-only — they never modify a project.

## pw-status.sh

One deterministic project-status report, in place of an agent reading five files by hand.

```bash
$PW_HOME/tooling/scripts/entities/pw-status.sh <slug>                  # full report
$PW_HOME/tooling/scripts/entities/pw-status.sh <slug> --skip-cli-check # omit the forge/CLI auth section
$PW_HOME/tooling/scripts/entities/pw-status.sh --selftest              # isolated temp-project smoke test
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
$PW_HOME/tooling/scripts/entities/pw-preflight.sh analyze      <slug>   # phase context|analysis + context/INDEX.md exists with ≥1 filled input row
$PW_HOME/tooling/scripts/entities/pw-preflight.sh execute      <slug>   # PLAN approved, phase valid, scope/model resolvable (allowlist + availability gate)
$PW_HOME/tooling/scripts/entities/pw-preflight.sh breakdown    <slug>   # analysis reviews approved, RFC open items resolved
$PW_HOME/tooling/scripts/entities/pw-preflight.sh ship         <slug>   # shippable tasks exist, verify passed
$PW_HOME/tooling/scripts/entities/pw-preflight.sh comments     <slug>   # ≥1 task has a linked MR (for /pw-ship <slug> comments — no 'done' requirement)
$PW_HOME/tooling/scripts/entities/pw-preflight.sh close        <slug>   # all tasks accepted
$PW_HOME/tooling/scripts/entities/pw-preflight.sh review <slug> [phase] # review files exist for phase: analysis|plan|task-plan|task-exec
```

**Output:** silent on success (exit `0`). On failure, exit `1` with one `pw-preflight: …` line —
it names the gate *and* the fix, e.g.:

```
pw-preflight: PLAN review gate not approved
  → fix: approve it in <project>/task/review/PLAN.review.md (## Sign-off row) or run /pw-review <slug>
```

**Reading failures:** every message is terminal for that command — do the named action, re-run.
Unknown command argument → usage line, also exit 1.

**When to use:** first step of `/pw-execute`, `/pw-breakdown`, `/pw-ship`, `/pw-close`,
`/pw-review`. Any agent invoked *without* a command re-runs the same pre-flight itself.

## pw-status.sh — project-state setters

The same script is the ONLY writer of dashboard/LOG state (commands call these; never
hand-edit the Status line or LOG.md):

```bash
$PW_HOME/tooling/scripts/entities/pw-status.sh log   <slug> <actor> <msg...>   # LOG.md bullet, dedup-guarded
$PW_HOME/tooling/scripts/entities/pw-status.sh status <slug> <phase> [--rewind]  # refuses backward moves
$PW_HOME/tooling/scripts/entities/pw-status.sh oneliner <slug> <text...>
$PW_HOME/tooling/scripts/entities/pw-status.sh adopted <slug> <text...>          # insert-or-replace, idempotent
$PW_HOME/tooling/scripts/entities/pw-status.sh phase  <slug>                     # read the Status token only
$PW_HOME/tooling/scripts/entities/pw-status.sh dashboard-task-status <slug> <T0n> <status>
$PW_HOME/tooling/scripts/entities/pw-status.sh task-accept <slug> <T0n>          # merged-MR acceptance flow
$PW_HOME/tooling/scripts/entities/pw-status.sh provider-audit <slug> [task-ids…] # report-only (below)
```

**`provider-audit`** compares each task row's `Execute with:` (expected) against the LOG.md spawn
ledger + the task's `Actually used:` (what ran), validates the row against the live catalog via
`pw-config.sh model-resolve`, and prints one pipe row per task:
`T0n|expected=…|used=<q[:model]|never-run>|via=…|route=…|verdict=ok|mismatch|stale-provider|unbound`.
`stale-provider` = the row pins a provider/api-provider gone from `PW_PROVIDERS`/
`PW_KILO_API_PROVIDERS` (the migration case); `unbound` = the model isn't in the catalog. Exit 0
iff nothing but `ok`/`never-run`; mutates nothing (no LOG line). Wired as a warning pass into
`/pw-execute`/`/pw-ship` and the `/pw-close` recap.

## pw-config.sh

Per-project config lines on the dashboard, get-or-set semantics:

```bash
$PW_HOME/tooling/scripts/entities/pw-config.sh ai-review <slug> [<phase> <mode>]        # off|advisory|auto
$PW_HOME/tooling/scripts/entities/pw-config.sh ai-model  <slug> [<lane> <provider:model|—>]
$PW_HOME/tooling/scripts/entities/pw-config.sh model-check <provider> <model-id>        # PERMISSION axis (allowlist guard)
$PW_HOME/tooling/scripts/entities/pw-config.sh model-resolve <provider> <model-id>      # AVAILABILITY axis (below)
```

`auto` is what lets `pw-review.sh auto-signoff` ever succeed; `model-check` reads
`PW_MODEL_ALLOWLIST_<PROVIDER>` from pw.config.sh (empty = all allowed). `/pw-review <slug>
config` is the human-facing surface for the first two — prefer it over calling the script.

**`model-resolve`** proves a model *exists right now* (model-check only proves it's *permitted*):
match against the provider's live catalog **exact-first** — the exact line wins, because the
agent-provider prefix is semantic, not cosmetic: `alibaba-token-plan/<m>` is a *direct* provider
line and `kilo/alibaba-token-plan/<m>` is the same BYOK registered *under* the gateway (different
connections, auth, billing); the prefix-less row falls back to the gateway line only when no
direct line exists, announcing the substitution on stderr. Then verify it sits inside the
`PW_<PROVIDER>_API_PROVIDERS` **prefix** scope, and print the
**canonical** catalog id (what `-m`/`--model` must receive). Exit `0` resolved (id on stdout) /
`1` not in catalog (candidates on stderr) / `2` out of configured scope (current entries on
stderr). Fails **open** on "can't check" (claude has no catalog; CLI off PATH; unknown provider) —
exit 0 + an "unverified" note — so every non-zero is a positive determination safe to hard-stop
on. `pw-preflight.sh execute` runs it per row; the routing ladder runs it before every spawn.

## pw-session.sh

Deterministic headless-session liveness — the resume gate. "Is this recorded `Session:` id still
resumable?" is a script answer, never an attempted-resume-and-read-the-error:

```bash
$PW_HOME/tooling/scripts/entities/pw-session.sh session-check <provider> <session-id>
$PW_HOME/tooling/scripts/entities/pw-session.sh session-check <slug> <task-id>   # reads provider+id from the task file
```

Exit `0` live / `1` dead-or-absent / `2` unverifiable (the conservative reading on the ladder is
"not resumable" → cold/inline path). Per-provider surfaces: kilo `kilo session list --format
json -a`; claude `~/.claude/projects/<cwd-encoded>/<id>.jsonl` (searched across all project dirs;
empty file = dead); cursor `~/.cursor/chats/<hash>/<id>/` (the `agent ls` TUI is not scriptable);
opencode has no verified surface yet → always `2` (implement it HERE when a machine with opencode
shows up, never in callers). Every lookup is a pure read — no model calls, no CLI resume attempt.

## pw-help.sh

Human renderings are **user-safe by default**: `overview` tags rows only by doctrine facet
(`(write)`/`(read)`/`(special)`/`(lifecycle)`), `command <name>` omits entity-script sections,
`tooling/docs` pointers, and bundle paths entirely — its runnable examples use `/pw-*` command
forms only. `command <name> --maintainer` adds the maintainer layers back (`operators <name>`
remains the explicit deep dump; `--json` carries the full raw machine view). Where the
user prose lives: every `command`/`overview` blurb is sourced from the command file's own
bullet/`literally <tok>` definition first (the script paragraph is the fallback and is shown
raw only under `--maintainer`), and whatever reaches a default view passes through
`user_prose` — the scrubber that rewrites internal terms (`pw-<x>.sh` → `/pw-<x>`,
the status view, operator-reference etc.) so a renderer edit can never re-leak them. `find`
defaults to the command files + docs; add `--maintainer` to search the internals surfaces.

The discovery surface (introspection family): renders *live* from command frontmatter,
script usage headers, and its own phase map — so it cannot drift from the surfaces it
describes, and the T4 canary fails CI if a new command skips its phase-map entry.

```bash
$PW_HOME/tooling/scripts/entities/pw-help.sh overview [--json]
$PW_HOME/tooling/scripts/entities/pw-help.sh operators <name> [<operator>]
$PW_HOME/tooling/scripts/entities/pw-help.sh project <slug> [<name>] [--json]
$PW_HOME/tooling/scripts/entities/pw-help.sh workflow [--json]
$PW_HOME/tooling/scripts/entities/pw-help.sh command <name> [<slug>] [--full|--json]
```

- `overview` — one line per command and per exposed operator (the command's own
  invocation shapes are the surface proof; a "literally `<op>`" definition line counts
  for sugar operators like `/pw-review config`), grouped by phase bucket. `--json`
  returns the stable machine shape (`cmd,args,summary,agent,scripts,facets,phase,ops[]`).
- `operators <name> [<operator>]` — the verbatim usage-header dump for the named
  command's entity/toolchain scripts (facet lines included), or one operator's deep-dive.
  Library scripts are not listable — they are source-only (L2); names echo in full
  canonical form (`pw-review`, never `review`).
- `workflow` — the phase spine with gate paths, from `PW_VALID_PHASES` + the phase map.
- `project <slug> [<name>]` — the project how-to: phase, most-likely-next lines with real
  targets, on-disk review/plan/task rows with gate + open-item states, and per-operator
  concretization with `<name>`. Its only subprocesses are reads: `pw-status.sh phase <slug>`,
  `pw-review.sh gate`/`count`, and `pw-config.sh ai-review <slug>` (get form, never with a
  mode argument) — pinned by the T1 case's call-site whitelists.
- `command <name> [<slug>]` — the how-to manual per command (Use when / Does / Shape /
  doctrine / runnable example per operator; `--full` = substituted source file).

Strictly read-only: opens files for read only, and calls only the read operators above;
invocation examples it prints are text, never executed. Exit 0 / 2 (unknown names carry a `→ fix:` + did-you-mean); zero-hit
renderings are not errors.
