# TOOLING.md — where the machinery lives

← [back to README](../README.md) · related: [Reference](./REFERENCE.md) · [Execution](./EXECUTION.md)

You never need this page to run projects — the `/pw-*` commands and the `project-workflow` skill
are the interface. `/pw-help` (bare, or `/pw-help command <name>`) is the live discovery surface
for every command, operator, and argument; `docs/REFERENCE.md` summarizes what you can update per
project. Operations are command-only: if a guide or message seems to ask you to run an internal
script, the equivalent `/pw-*` command is the supported way.

This page exists for one purpose: pinning where the machinery lives. Everything the commands call
underneath is the bundle's `tooling/` tree, next to this `docs/` directory — the `/pw-*` command
sources, the sub-agent definitions, the shipped skills, the maintainer reference docs, and the
regression harness that guards all of it.

Three facts worth knowing before you poke around:

- **Sources-only.** Everything under `tooling/` is the single source of truth; the copies in
  `~/.claude/`, `~/.cursor/`, `~/.config/kilo/`, … are generated. A fix made only in a generated
  copy is destroyed by the next `/pw-doctor --fix` — move it into the source and regenerate.
- **The harness guards the boundary.** Doctrine like command-only guidance is mechanically tested:
  user docs, templates, and generated output stay behavioral and name `/pw-*` commands; maintainer
  docs stay mechanism-side; published files carry no internal planning references.
- **Maintainer onboarding starts at `tooling/AGENTS.md`** in the bundle repo — the per-directory
  convention file, which points into the maintainer reference tree. This page deliberately carries
  no deep links: curious users get one address, and maintainers stop being users the moment they
  open it.
