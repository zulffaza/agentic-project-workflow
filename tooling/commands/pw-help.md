---
description: One discovery surface for the whole tooling - what commands/operators exist, how to invoke them, and what applies globally (overview, how-to per command, operator dumps, workflow spine)
args: '[overview | command <name> [<slug>] [--full|--json] | operators <name> [<operator>] | workflow] [--json]'
---
The group in ``args`` is the operator; a bare `/pw-help` means `overview`. (`/pw-help` is the
documented C1 exception where the first argument is the operator, not the slug — help's subject
is the bundle, projects appear only inside the `project` operator later.)

**This command is a mechanical mapping (C3): run the script and show its output verbatim. No
judgment, no doc reading — help renders from the live sources (command frontmatter, script
usage headers, the phase map), so its answer can never be a stale snapshot.**

The operators:

- **`/pw-help overview`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh overview` — every
  command, one line per exposed operator with its use case, grouped by phase bucket.
- **`/pw-help command <name> [<slug>]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh
  command <name> [<slug>]` — the how-to manual for one command: per-operator Use-when/Does/
  Shape/doctrine blocks lifted from this command file + the entity's usage header, the entity
  script's facet-grouped operator signatures, and doc pointers. `--full` renders this file
  verbatim (placeholders substituted) for the rare reader needing all the doctrine; `--json`
  is the machine shape.
- **`/pw-help operators <name> [<operator>]`** → passed verbatim — the verbatim usage-header
  dump for the named command's entity/toolchain scripts (or one operator's deep-dive). Bare
  library scripts are deliberately not listable — they are source-only (L2 in
  `{{PW_HOME}}/tooling/docs/conventions.md`).
- **`/pw-help workflow`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh workflow` — the
  phase spine (commands per phase, gate files) plus side-loop and any-time commands.

`--json` modes are the stable machine interface (bounded, exit-coded, stable keys). Agents:
this is the token-cheap way to learn the operator surface — prefer it over reading command
files; run help when the *user* asks what's available or when you must locate a capability.
Help is introspection — it renders doctrine, never replaces it, and never makes gate
decisions. Unknown names exit 2 with a `→ fix:` hint; names are always echoed in full
`pw-<name>` form (bare input like `review` is accepted and normalized).
