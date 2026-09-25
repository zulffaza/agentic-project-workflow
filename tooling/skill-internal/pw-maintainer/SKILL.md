---
name: pw-maintainer
description: Maintainer cheat-sheet for changing the agentic-project-workflow bundle itself. Use when asked to change or maintain the bundle — edit anything under tooling/ or template/, add or rename a command / operator / script / agent / skill, write or re-pin a mutation row, run the test harness, decide where new capability goes, or diagnose "pw-doctor reports out of sync". Loads the sources-only doctrine, the change-and-test protocol, the S/L/C/A/D placement conventions, and the user-vs-maintainer doc boundary on demand. NOT for running a project through the /pw-* pipeline — that is the project-workflow skill.
---

# pw-maintainer — changing the bundle

You are about to **change the machinery**: anything under `tooling/` (scripts, commands, agents,
skill sources, generators, docs, the test harness) or `template/`, or a generated provider surface.
This skill is the navigational front door — a thin map over the canonical maintainer docs so you
load only the detail the current change needs. It owns **no** rules of its own: every rule lives in
the doc it points to, so if a rule changes, the doc changes and this map stays valid.

> **Driving a project instead?** Running a change through context → analysis → breakdown →
> execution → review → close with the `/pw-*` commands is the **`project-workflow`** skill, not this
> one. This skill is for editing the bundle that *produces* those commands.

**Read the canonical maintainer entry point first:** [`tooling/AGENTS.md`](../../AGENTS.md) — the
doctrine, the implementation map, and the change/test protocol. Then load the one reference below
that matches your task.

## Golden doctrine (always true — no reference needed)

- **Sources only.** `tooling/` and `template/` are the single source of truth; the per-provider
  copies (`~/.claude`, `~/.cursor`, `~/.config/kilo`, …) are **generated**. Never hand-edit a
  generated copy — `pw-doctor.sh --fix` regenerates it and destroys anything that lived only there.
  A fix made to a live copy must be **moved into the source, then regenerated**.
- **Mutate project state through the entity scripts**, never by hand-editing load-bearing lines:
  `pw-status.sh` (dashboard / LOG / phase), `pw-review.sh` (review files / gates), `pw-context.sh`
  (context docs), `pw-config.sh` (per-project config).
- **New shared logic goes in the libraries**, not re-implemented in a caller: `pw-common.sh`
  (project-state + env/forge primitives), `pw-mdlib.sh` (pure markdown-document primitives). The old
  frozen core `pw-lib.sh` is fully dissolved — do not resurrect it.
- **Test after ANY change** under `tooling/` or `template/`. A change to a documented format or
  contract also needs a **mutation row** that bites: revert the fix and a test must fail.
- **Respect the information boundary.** Internal mechanics and plan numbers never reach user docs.
  Two specifics bite hardest — full treatment in
  [`references/boundary-and-docs.md`](references/boundary-and-docs.md): **shipped docs are
  self-contained** (no plan-local jargon — rule labels, tier/task refs, `rev x` — in user prose;
  define a term in place or don't use it), and **the user layer never references `tooling/`** —
  strict since the 2026-09-25 sweep, mechanically canaried, with exactly one sanctioned exit:
  the `docs/TOOLING.md` hub (root `AGENTS.md` is a pure user file — maintainers onboard via
  `tooling/AGENTS.md` directly). User-relevant mechanics
  that can't live in a user doc alone get a **registered twin** pair (D5, duplication registry in
  `conventions.md`).

## Which reference do I load?

| You're asked to… | Load |
|---|---|
| make any change and prove it's safe (the ordered loop) | [`references/change-protocol.md`](references/change-protocol.md) |
| decide *where* a new script / command / operator / argument goes | [`references/conventions-nav.md`](references/conventions-nav.md) |
| run the harness, pick test tiers, author or re-pin a mutation row | [`references/testing-harness.md`](references/testing-harness.md) |
| check what may leak to users, or write / update docs & plan files | [`references/boundary-and-docs.md`](references/boundary-and-docs.md) |
| need a script's exact operators, exit codes, and fix hints | [`tooling/docs/scripts/README.md`](../../docs/scripts/README.md) — the usage reference |
| need the live command / operator map (read-only) | `pw-help.sh overview` · `command <name>` · `operators <name>` · `find <term>` |

`pw-maintainer` is a **reserved name** — never reuse it for a `/pw-*` user command or a
`tooling/skill/` user skill. The durable reservation lives in
[`tooling/docs/conventions.md`](../../docs/conventions.md) beside the C-rules.
