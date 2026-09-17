# Capability-placement conventions (scripts, layout, commands, arguments)

**Audience:** maintainers (human or agent) adding capability to this bundle. Read this BEFORE
creating a script, a slash command, or an operator — it answers "where does this go?" twice over:
which **script** (S-rules), which **directory** (L-rules), which **command** (C-rules), and how
arguments are **shaped** (A-rules). The lesson it encodes: `pw-lib.sh` grew to 2095 lines because
placement was never defined; it is now dissolved (see S2) and the layout under `tooling/scripts/`
is normative.

## S-rules — where script capability lives

- **S1 — one script per entity.** The entity is the noun the operations act on: review-doc
  (`pw-review.sh`), context-doc (`pw-context.sh`), ship/MR (`pw-ship.sh`), worktree
  (`pw-worktree.sh`), rfc-doc (`pw-rfc.sh`), docs (`pw-doc.sh`), project-state (`pw-status.sh`),
  config (`pw-config.sh`). All operators on an entity live in that entity's script.
- **S1a — entity granularity.** An entity is the **artifact family an operator acts on**, not the
  verb and not the read/write split. `scan` belongs to review-doc; lint/summary/sync belong to
  docs; two scripts touching the same artifact family = an S1 violation.
- **S1b — facets: the second-level split.** Operators inside an entity script are grouped into
  **facets** — `write` / `read` / `lifecycle` (or verb-families like lint/summary/sync for docs) —
  declared as labeled sections of the usage header (S6). The entity↔command mapping stays 1:1
  (C1); entity↔script may become 1:≤2. When an entity script hits the S3 trigger (~1000 lines):
  **(1)** push shared primitives down to `scripts/lib/` (S5) — usually sufficient; **(2)** if
  still over, mint a facet script `pw-<entity>-<facet>.sh` — allowed only when the facet carries
  ≥5 operators with a coherent audience (e.g. the read-only facet other scripts/commands consume);
  **(3)** the entity's command file routes operators across the two scripts mechanically (C3),
  the registry lists both, and the docs/scripts index symmetry check is unchanged.
  Never split mid-facet by verb family; never split below the trigger.
- **S2 — there is no second `pw-lib.sh`.** The legacy catch-all was FROZEN (no new subcommands)
  and then fully dissolved into entity scripts + `scripts/lib/` primitives; its `# FROZEN (S2`
  header and the T0 dead-path canary keep the history honest. Anything that does not belong to
  one entity belongs in a source-only library (S5) — never in a shared mutable core.
- **S3 — split trigger.** A script grows operators for a *second* entity, or passes ~1000 lines
  → split by entity (S1) or facet (S1b). Don't wait for 2000.
- **S4 — anti-flood trigger.** Never mint a new script for fewer than 3 operators on an
  *existing* entity — add the operator to that entity's script. Single-purpose micro-scripts are
  forbidden; shared logic goes to a source-only library (S5), not a new entry point.
- **S5 — shared code = source-only `pw-*lib.sh` libraries in `tooling/scripts/lib/`.**
  - `pw-common.sh` — env/provider/forge plumbing; every entry-point script sources it.
  - `pw-mdlib.sh` — pure markdown-document primitives (comment-blanking, review-item detection,
    sign-off row reads, table splice helpers). Takes explicit file paths, knows nothing about
    slugs or projects. If two scripts need the same document primitive, it belongs here.
  - `pw-projectlib.sh` — project-state primitives (slug→project resolution, dashboard reads).
  - Libraries never dispatch, never `exit`, and are never executable entry points.
- **S6 — house style** (all entry-point scripts): `set -euo pipefail`; `case "${1:-}"` dispatch;
  usage header comment block (one paragraph per operator, grouped under its facet label — this is
  the operator's primary doc); `-h`/`--help` exits 0; `die`-style errors to stderr prefixed with
  the script name, always carrying a `→ fix:` style remediation hint; `<slug>` first arg;
  project-relative paths; bash 3.2 compatible; `--selftest` delegating to the harness.
- **S7 — migration policy.** Moving/renaming/dissolving a script updates **every** reference in
  the same commit: commands, agents, skills, tests (registry, case files, canaries, fixture
  builders, cache-recipe paths), docs, templates, `bootstrap.sh`/`offboard.sh` — **and
  mutation-register rows** whose anchors move with the code (re-pin and re-verify in the same
  commit; see `testing.md` §Writing a mutation row). After the commit, a T0 dead-path canary must
  find zero references to the old path/name. No silent shims: either every reference moves, or an
  explicit deprecation forwarding is documented and time-boxed here — the default is a hard cut.

## L-rules — directory layout (all scripts live under `tooling/scripts/`)

- **L1 — `tooling/scripts/entities/`** = per-entity automation entry points (the
  `PWTEST_AUTOMATION` registry). These are what commands/agents/skills invoke.
- **L2 — `tooling/scripts/lib/`** = source-only libraries (S5). A T0 canary asserts no entry path
  (commands/agents/skill) mentions a `lib/` file — libraries are invisible to callers.
- **L3 — `tooling/scripts/toolchain/`** = bundle-maintenance scripts (`scaffold.sh`,
  `gen-commands.sh`, `gen-agents.sh`, `pw-doctor.sh`). **The toolchain test:** a script is
  toolchain iff its operand is **the bundle itself** — it creates, generates, installs, or
  validates tooling/template/provider state — never the artifact state of an existing project.
  Litmus: delete every project under `$PW_PROJECTS_DIR` and the script still has work to do.
  Consequences: never in the automation registry; referenced only by maintainer surfaces
  (`bootstrap.sh`, `offboard.sh`, root/tooling docs) plus exactly one allowlisted workflow
  surface — `/pw-doctor` → `toolchain/pw-doctor.sh`. A T0 canary enforces the allowlist
  (`tooling/tests/expectations/toolchain.ok`).
- **L4 — naming.** Entity entry point = `pw-<entity>.sh` (or `pw-<entity>-<facet>.sh` per S1b),
  noun-of-the-entity; library = `pw-<name>lib.sh`; verb-only or micro-purpose names
  (`pw-adopt-snapshot.sh` ✗) are invalid. Toolchain keeps its historical names.
- **L5 — reference form.** `$PW_HOME/tooling/scripts/entities/<name>.sh` (shell) /
  `{{PW_HOME}}/tooling/scripts/entities/<name>.sh` (prompt files); toolchain refs
  `$PW_HOME/tooling/scripts/toolchain/<name>.sh`; intra-bundle sourcing uses
  `$HERE/../lib/<name>.sh`. The old flat form `tooling/<name>.sh` fails a T0 canary.

## C-rules — how slash commands are shaped

- **C1 — one command per entity; first argument is the operator.** A no-operator invocation keeps
  the command's original behavior (`/pw-review <slug>` alone = the AI-review round).
- **C2 — new behavior on an existing entity → new operator on that entity's command.** New
  behavior that is actually a *different* entity → a separate command. Never bolt a second entity
  onto an existing command, and never mint a command named after one operator
  (`/pw-context-add` ✗ → `/pw-context … add-input` ✓).
- **C3 — command files are mechanical operator→script mappings.** The agent's job is: locate the
  project/doc, parse args per the A-rules, hand each value to the script quote-safe, show the
  script's output. No prose judgment, no doc re-reading, no "improvising" the edit by hand when
  an operator exists.
- **C4 — doctrine-restricted operators** (e.g. `review signoff` — "only a human clears a gate")
  are labeled **"human-triggered only, never on agent initiative"** in the command file, and a T0
  anti-idiom static test asserts no agent file mentions them.

## A-rules — arguments that contain spaces (free text)

Slash-command args are space-separated, but asks/answers/provenance prose contain spaces. This is
safe because the agent mediates (C3): the user's raw line is parsed by the command file's rules,
and the script only ever receives already-separated values — it never splits spaces itself.

- **A1 — rest-of-line slot.** An operator has *at most one* free-text slot, and it is always the
  **last** argument. Everything after the last fixed positional is the text; the user never
  quotes:

  ```
  /pw-review myproj item analysis/review/topic.review.md §4 the toggle also lives in common-config, add a row
  └─ fixed: slug, operator, path, section ─────────────┘ └─ rest-of-line: the ask ─────────────────────────┘
  ```

- **A2 — flag-segment form** for the rare operator with *two* prose fields: `--flag` segments
  where **each value runs until the next `--flag` token** — a deterministic split, still no
  quoting:

  ```
  /pw-context myproj add-input --file spring-rfc.md --what Migration RFC excerpt --source Lark doc docs/xxxx --trust Approved RFC
  ```

- **A3 — quote-safe handoff.** The agent passes each parsed value to the script via `--stdin`
  heredoc (preferred — survives quotes, backticks, and multi-line prose) or as a single
  shell-quoted argv. The script takes the value verbatim and never re-parses.
- **A4** — new operators follow A1 by default; A2 only when a second prose field is unavoidable.

## Checklist for adding capability

1. Which entity? → its script in `tooling/scripts/entities/` (S1/S1a). No script yet and ≥3
   operators? → create one (S4). Script past ~1000 lines? → lib extraction, then S1b facet split.
2. Shared document primitive? → `scripts/lib/pw-mdlib.sh` (S5). Project-state primitive? →
   `scripts/lib/pw-projectlib.sh`. Env/forge? → `scripts/lib/pw-common.sh`.
3. Tempted to add a catch-all core? → don't (S2). Operating on the bundle itself? → toolchain (L3).
4. Command surface: operator on the entity's existing command (C1/C2); mechanical mapping (C3);
   human-only? → C4 label + static test.
5. Prose argument? → A1 rest-of-line; two prose fields → A2 flag segments; handoff via A3.
6. Docs before ship: usage header (S6) + a section in `docs/scripts/` + command file + affected
   skills/agents/templates. **No doc-less capability ships.**
7. Tests before ship: T1 selftest cases + battery rows + mutation-register catchers — see
   [`testing.md`](./testing.md). Register rows: OLD byte-exact **and unique**, catcher must not
   depend on the mutation changing fixture BYTES (recipe-hash cache rule), check next-free ID
   against draft reservations — checklist in [`testing.md`](./testing.md) §Writing a mutation row.
8. Moving or renaming a script? → S7: every reference (including register anchors) updates in the
   same commit; the dead-path canary must go green with the commit, not after it.
