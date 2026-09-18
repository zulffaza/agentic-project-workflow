---
description: One discovery surface for the whole tooling - what commands/operators exist, how to invoke them, and what applies to a project right now (overview, per-command how-to, operator dumps, phase spine, literal-term search)
args: '[overview | command <name> [<slug>] [--full|--json|--maintainer] | operators <name> [<operator>] | project <slug> [<name>] | workflow | find <term>] [--json]'
---
The leading group in `args` is the operator; a bare `/pw-help` shows the overview. (`/pw-help`
is the documented C1 exception where the first argument is the operator, not the slug — help's
subject is the bundle; projects appear only inside the `project` operator and the `command`
operator's optional slug slot.)

**This command is a mechanical mapping (C3): run the script and show its output verbatim. No
judgment, no doc reading — help renders from the live sources (command frontmatter, script
usage headers, the phase map), so its answer can never be a stale snapshot. The script's output
IS your reply: paste it into a fenced code block in your response — never paraphrase, re-wrap,
summarize, decorate it, or refer to it as "the output above" (a code block preserves the
renderer's columns and ASCII alignment exactly as emitted).**

The operators:

- **`/pw-help overview`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh overview` — every
  command, one line per exposed operator with its use case, grouped by phase bucket.
- **`/pw-help command <name> [<slug>]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh
  command <name> [<slug>]` — the how-to manual for one command: per-operator Use-when / Does /
  Shape / doctrine / runnable-example blocks lifted from the command file and the entity
  script's usage header, plus user-surface doc pointers. The default human view is command
  surface only — end-user safe. `--maintainer` adds the entity-script sections (paths +
  operator signatures) and tooling/docs pointers; `operators <name>` stays the explicit deep
  dump. `--full`
  prints the whole (substituted) command file; `--json` the machine shape.
- **`/pw-help operators <name> [<operator>]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh
  operators <name> [<operator>]` (args pass through verbatim) — the usage-header dump for the
  named command's entity/toolchain scripts, or one operator's paragraph deep dive. Bare library
  scripts are deliberately not listable — they are source-only (L2).
- **`/pw-help project <slug> [<name>]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh
  project <slug> [<name>]` — what applies to a REAL project right now: phase, the
  most-likely-next lines with existing targets filled, files found on disk with gate/open
  states, and one command's operators concretized with `<name>`. Read-only: only the state
  reader's `phase`, review `gate`/`count` reads, and `pw-config.sh ai-review <slug>` (get form)
  are ever invoked; the command lines it prints are text, never executed.
- **`/pw-help workflow`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh workflow` — the
  phase spine with gate paths, plus side-loop and any-time commands.
- **`/pw-help find <term>`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh find` with the
  rest-of-line as ONE literal case-insensitive phrase (A1) — searches command files, entity +
  toolchain scripts, tooling docs and root docs (never library sources, never corpus
  projects). Output is a capped list of `surface path:line  snippet`; zero hits exits 0 with a
  hint. Agents: `find <term> --json` is the token-cheap way to locate a concept across the
  tooling surface instead of exploratory greps.

All renderings echo names in FULL canonical form (`pw-review`, never `review`) and accept bare
input; unknown names exit 2 with a `→ fix:` hint and a did-you-mean when close. `--json` is
the stable machine interface (bounded, exit-coded, stable keys — the only contract surface;
human tables may reflow). Agents: help is the token-cheap way to learn an operator surface —
prefer it over reading command files; run it when the *user* asks what's available or when a
capability must be located. Help is introspection: it renders doctrine, never replaces it, and
never makes gate decisions.
