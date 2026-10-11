---
description: One discovery surface for the workflow - what commands and operators exist, how to invoke them, and what applies to a project right now (overview, per-command how-to, operator deep dives, phase spine, literal-term search)
args: "[overview | command | operators | project | workflow | find] [--name <name>] [--project <project-slug>] [--term <term…>] [--full|--json|--maintainer]"
scope: mixed
scope-forms: "default=global, overview=global, command=global, operators=global, workflow=global, find=global, project=project"
args-global: "[overview | command --name <name> [--project <project-slug>] [--full|--json|--maintainer] | operators --name <name> [--operator <op>] | workflow | find --term <term…>] [--json]"
args-project: "project --project <project-slug> [--name <command>] [--json]"
---
The first word is the operator; every value is named (operator words first — named-argument
grammar). A bare `/pw-help` — my message carries NO operator word — maps to `overview`: that is
the invocation. Never guess an operator from this file's own example lines; only words I
actually typed after `/pw-help ` select one. (`/pw-help` is the documented C1 default-flow
exception — help's subject is the bundle; a project is selected only with `--project <slug>` on
the `project` operator, or contextually on `command`.)

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
- **`/pw-help overview [--json]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh overview [--json]` — every
  command, one line per exposed operator with its use case, grouped as Global Operations
  (no existing workflow project required) and Project Operations (explicitly select
  `--project <slug>`; Create or Attach labeled separately, then the phase buckets).
- **`/pw-help command --name <name> [--project <slug>] [--full|--json|--maintainer]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh
  command --name <name> [--project <slug>] [--full|--json|--maintainer]` — the how-to manual for one command: per-operator blocks (when to
  use it, what it does, its declared scope, its doctrine labels, a runnable example line) with pointers
  to the matching user docs. The default view is the command surface only — end-user safe.
  `--maintainer` additionally shows the internals sections (file names + signatures) and the
  internal-doc pointers; `operators --name <name>` stays the explicit deep dive. `--full` prints the
  whole (substituted) command file; `--json` gives the machine shape (scope fields included).
- **`/pw-help operators --name <name> [--operator <op>]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh
  operators --name <name> [--operator <op>]` (args pass through verbatim) — the maintainer deep dive: the
  full operator reference for the named command's internals, or one operator's paragraph.
  Library internals are deliberately not listable.
- **`/pw-help project --project <slug> [--name <command>] [--json]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh
  project --project <slug> [--name <command>] [--json]` — what applies to a REAL project right now: phase, the
  most-likely-next lines with existing targets filled, files found on disk with gate/open
  states, and one command's project-scope operators concretized with `--name` (a mixed command's
  global forms render as a separate footer, never with the project attached). Read-only — it only
  looks at the project's current status; the command lines it prints are text, never executed.
- **`/pw-help workflow [--json]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh workflow [--json]` — the
  phase spine with gate paths, plus side-loop and any-time commands.
- **`/pw-help find --term <term…> [--json] [--maintainer]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh find`
  with the term as ONE literal case-insensitive phrase (`--term` is a prose flag — it runs until
  the next `--flag` token) — by default searches the command
  files and the user docs (never library sources, never project files); add `--maintainer` (or
  use it yourself as an agent) to also search the internals: operator references, tooling docs,
  script headers. Output is one line per hit with the file, line number, and the full matched
  text — nothing is shortened; zero hits exits 0 with a hint. Agents: `find --term <term…> --json` is
  the token-cheap way to locate a concept across the tooling surface instead of exploratory
  greps.

All renderings echo names in FULL canonical form (`pw-review`, never `review`) and accept bare
input; unknown names exit 2 with a `→ fix:` hint and a did-you-mean when close. Unknown flags
and stray positional values fail closed with the replacement shape. `--json` is
the stable machine interface (bounded, exit-coded, stable keys — the only contract surface;
human tables may reflow). Agents: help is the token-cheap way to learn an operator surface —
prefer it over reading command files; run it when the *user* asks what's available or when a
capability must be located. Help is introspection: it renders doctrine, never replaces it, and
never makes gate decisions.
