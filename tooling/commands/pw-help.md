---
description: One discovery surface for the workflow - what commands and operators exist, how to invoke them, and what applies to a project right now (overview, per-command how-to, operator deep dives, phase spine, literal-term search)
args: '[overview | command <name> [<slug>] [--full|--json|--maintainer] | operators <name> [<operator>] | project <slug> [<name>] | workflow | find <term>] [--json]'
---
The leading group in `args` is the operator. A bare `/pw-help` — my message carries NO operator
argument — maps to `overview`: that is the invocation. Never guess an operator from this file's
own example lines; only words I actually typed after `/pw-help ` select one. (`/pw-help`
is the documented C1 exception where the first argument is the operator, not the slug — help's
subject is the bundle; projects appear only inside the `project` operator and the `command`
operator's optional slug slot.)

**This command is a mechanical mapping (C3): run the script and show its output verbatim. No
judgment, no doc reading — help renders from the live sources (the command files and the
operators' own references), so its answer can never be a stale snapshot. The script's output
IS your reply: paste it into a fenced code block in your response — never paraphrase, re-wrap,
summarize, decorate it, or refer to it as "the output above" (a code block preserves the
renderer's columns and ASCII alignment exactly as emitted).**

The operators:

- **`/pw-help` bare (no operator typed)** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh overview` —
  the DEFAULT mapping when my message has no arguments: identical to `overview` below, nothing
  else is assumed.
- **`/pw-help overview`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh overview` — every
  command, one line per exposed operator with its use case, grouped by phase bucket.
- **`/pw-help command <name> [<slug>]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh
  command <name> [<slug>]` — the how-to manual for one command: per-operator blocks (when to
  use it, what it does, its shape, its doctrine labels, a runnable example line) with pointers
  to the matching user docs. The default view is the command surface only — end-user safe.
  `--maintainer` additionally shows the internals sections (file names + signatures) and the
  internal-doc pointers; `operators <name>` stays the explicit deep dive. `--full` prints the
  whole (substituted) command file; `--json` gives the machine shape.
- **`/pw-help operators <name> [<operator>]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh
  operators <name> [<operator>]` (args pass through verbatim) — the maintainer deep dive: the
  full operator reference for the named command's internals, or one operator's paragraph.
  Library internals are deliberately not listable.
- **`/pw-help project <slug> [<name>]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh
  project <slug> [<name>]` — what applies to a REAL project right now: phase, the
  most-likely-next lines with existing targets filled, files found on disk with gate/open
  states, and one command's operators concretized with `<name>`. Read-only — it only looks at
  the project's current status; the command lines it prints are text, never executed.
- **`/pw-help workflow`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh workflow` — the
  phase spine with gate paths, plus side-loop and any-time commands.
- **`/pw-help find <term>`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh find` with the
  rest-of-line as ONE literal case-insensitive phrase (A1) — by default searches the command
  files and the user docs (never library sources, never project files); add `--maintainer` (or
  use it yourself as an agent) to also search the internals: operator references, tooling docs,
  script headers. Output is one line per hit with the file, line number, and the full matched
  text — nothing is shortened; zero hits exits 0 with a hint. Agents: `find <term> --json` is
  the token-cheap way to locate a concept across the tooling surface instead of exploratory
  greps.

All renderings echo names in FULL canonical form (`pw-review`, never `review`) and accept bare
input; unknown names exit 2 with a `→ fix:` hint and a did-you-mean when close. `--json` is
the stable machine interface (bounded, exit-coded, stable keys — the only contract surface;
human tables may reflow). Agents: help is the token-cheap way to learn an operator surface —
prefer it over reading command files; run it when the *user* asks what's available or when a
capability must be located. Help is introspection: it renders doctrine, never replaces it, and
never makes gate decisions.
