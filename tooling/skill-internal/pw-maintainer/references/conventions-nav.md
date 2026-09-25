# Conventions navigator — where does this go?

Canonical rules: [`tooling/docs/conventions.md`](../../../docs/conventions.md) — the doc every
contributor reads before adding capability. This page is the one-line gloss + which section to open;
the doc owns the full text.

| Adding / changing… | Rule family → section in `conventions.md` |
|---|---|
| A script — new capability, or where an operator lives | **S-rules** — one script per entity; S1a artifact-family granularity, S1b facets for the second-level split; S4 create-a-script threshold; S5 shared primitives → `lib/`; S6 usage header; S7 a rename/move updates every reference (incl. register anchors) in the same commit |
| Where a file lives on disk | **L-rules** — everything under `scripts/{entities,lib,toolchain}/`, decided by the *toolchain test*: operand = the bundle itself ⇒ `toolchain/` (never in the automation registry); operand = a project ⇒ `entities/`; a pure reusable primitive ⇒ `lib/` |
| A slash command or operator | **C-rules** — one command per entity, first argument is the operator (C1); new behavior → a new operator, not a new command (C2); command files are mechanical operator→script mappings, output shown verbatim fenced (C3); doctrine-restricted operators get a human-only label + a static test (C4) |
| An argument that contains spaces | **A-rules** — A1 rest-of-line slot (at most one, always last); A2 flag-segment form for two prose fields; A3 quote-safe handoff (`--stdin` heredoc) |
| Where knowledge or an issue record lives | **D-rules** — D1 layers (`docs/` user vs `tooling/docs/` maintainer), D2 issue routing, D3 self-contained user layer, D4 "known issue = a maintainer state". See also [boundary-and-docs.md](boundary-and-docs.md) |

**Decision aid:** adding a script → S + L; adding a command or operator → C; adding an argument →
A; placing a doc or an issue record → D. When in doubt, the **Checklist for adding capability** at
the end of [`conventions.md`](../../../docs/conventions.md) walks the whole sequence (entity → lib →
command surface → args → docs → tests).

**Reserved names.** `pw-maintainer` (this skill) is reserved — never reuse it for a `/pw-*` user
command or a `tooling/skill/` user skill. The durable note lives in
[`conventions.md`](../../../docs/conventions.md) beside the C-rules; add any future reservation there
too, so the registry outlives whichever plan proposed it.
