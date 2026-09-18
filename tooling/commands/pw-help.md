---
description: One discovery surface for the whole tooling - what commands/operators exist and how to invoke them (overview, operator dumps, workflow spine)
args: [operators <name> [<operator>] | workflow] [--json]
---
Operator is optional: bare `/pw-help` = the global overview.

**This command is a mechanical mapping (C3): run the script and show its output verbatim. No
judgment, no doc reading — help renders from the live sources (command frontmatter, script
usage headers, the phase map), so its answer can never be a stale snapshot.**

The operators:

- **`/pw-help`** → `{{PW_HOME}}/tooling/scripts/entities/pw-help.sh overview` — every command,
  one line per exposed operator with its use case, grouped by phase bucket.
- **`/pw-help operators <name> [<operator>]`** → passed verbatim — the verbatim usage-header
  dump for the named command's entity/toolchain scripts (or just one operator's paragraph).
  Bare library scripts are deliberately not listable — they are source-only (L2 in
  `{{PW_HOME}}/tooling/docs/conventions.md`).
- **`/pw-help workflow`** → passed verbatim — the phase spine (commands per phase, gate files)
  plus side-loop and any-time commands.

`--json` on overview/workflow is the stable machine interface (bounded, exit-coded, stable
keys). Agents: this is the token-cheap way to learn the operator surface — prefer it over
reading command files; run help when the *user* asks what's available or when you must locate
a capability. Help is introspection — it renders doctrine, never replaces it, and never makes
gate decisions. Unknown names exit 2 with a `→ fix:` hint; names are always echoed in full
`pw-<name>` form (bare input like `review` is accepted and normalized).
