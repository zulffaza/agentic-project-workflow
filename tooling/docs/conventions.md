# Capability-placement conventions (scripts, commands, arguments)

**Audience:** maintainers (human or agent) adding capability to this bundle. Read this BEFORE
creating a script, a slash command, or an operator — it answers "where does this go?" so
`pw-lib.sh` (2204 lines at the time of writing) never happens again and the tooling dir never
floods with single-purpose micro-scripts.

## S-rules — where script capability lives

- **S1 — one script per entity.** The entity is the noun the operations act on: review-doc
  (`pw-review-edit.sh`), context-doc (`pw-context.sh`), ship (`pw-ship-*.sh`), status
  (`pw-status.sh`), doc validation (`pw-doc-*.sh`)… All operators on an entity live in that
  entity's script.
- **S2 — `pw-lib.sh` is FROZEN.** No new subcommands. It remains the legacy core
  (dashboard/status/log/phase/gate reads, rfc/ship state) until a dedicated migration plan splits
  the remainder per S1. New scripts reuse its logic only via shared libraries (S5).
- **S3 — split trigger.** A script grows operators for a *second* entity, or passes ~1000 lines
  → split by entity. Don't wait for 2000.
- **S4 — anti-flood trigger.** Never mint a new top-level script for fewer than 3 operators on an
  *existing* entity — add the operator to that entity's script. Single-purpose micro-scripts are
  forbidden; shared logic goes to a source-only library (S5), not a new entry point.
- **S5 — shared code = source-only `pw-*lib.sh` libraries.**
  - `pw-common.sh` — env/provider/forge plumbing; every entry-point script sources it.
  - `pw-mdlib.sh` — pure markdown-document primitives (comment-blanking, review-item detection,
    sign-off row reads, table splice helpers). Takes explicit file paths, knows nothing about
    slugs or projects. If two scripts need the same document primitive, it belongs here.
  - Libraries never dispatch, never `exit`, and are never executable entry points.
- **S6 — house style** (all entry-point scripts): `set -euo pipefail`; `case "${1:-}"` dispatch;
  usage header comment block (one paragraph per operator — this is the operator's primary doc);
  `-h`/`--help` exits 0; `die`-style errors to stderr prefixed with the script name, always
  carrying a `→ fix:` style remediation hint; `<slug>` first arg; project-relative paths;
  bash 3.2 compatible; `--selftest` delegating to the harness.

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

1. Which entity? → its script (S1). No script yet and ≥3 operators? → create one (S4).
2. Shared document primitive? → `pw-mdlib.sh` (S5). Env/forge? → `pw-common.sh`.
3. Tempted to add a `pw-lib.sh` subcommand? → don't (S2).
4. Command surface: operator on the entity's existing command (C1/C2); mechanical mapping (C3);
   human-only? → C4 label + static test.
5. Prose argument? → A1 rest-of-line; two prose fields → A2 flag segments; handoff via A3.
6. Docs before ship: usage header (S6) + a section in `docs/scripts/` + command file + affected
   skills/agents/templates. **No doc-less capability ships.**
7. Tests before ship: T1 selftest cases + battery rows + mutation-register catchers — see
   [`testing.md`](./testing.md). Register rows: OLD byte-exact **and unique**, catcher must not
   depend on the mutation changing fixture BYTES (recipe-hash cache rule), check next-free ID
   against draft reservations — checklist in [`testing.md`](./testing.md) §Writing a mutation row.
