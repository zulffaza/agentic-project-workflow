---
description: The one per-project config surface — show/get/set validated knobs (routing, limits, models, review outcome/scheduling/repair axes, RFC target), plus the effective global floors
args: <project-slug> [show | get <key> | set <key> <value…> | ensure | global show | model-check <provider> <model-id>]
---
Arguments: {{ARGS}}. Project dir: `{{PW_PROJECTS}}/<slug>`.

**This command is a mechanical mapping (C3): parse my words into one script call below, run it,
and show its output.** Configuration lives in the project's own docs (dashboard/PLAN/task files/
RFC META) — this command is the *validated lens* over them; there is no separate config file, and
you never hand-edit those lines — the script owns them, validates every write, and logs it to
`LOG.md`. When I ask "what can I change?", run **`show`** — it lists every key with its kind and
where it is stored.

**No-slug forms:** when the 1st argument is literally `global` or literally `model-check`, there
is no `<project-slug>` — those two operators address the machine side (floors, validators), never
project files.

The keys you can `set`, and their legal values (the same list `show` prints as its footer):

| key | settable to | meaning of the value |
|---|---|---|
| `routing` | `auto` · `subagent` · `headless` | default route for every task; `headless` = **strict** model binding, no silent downgrade |
| `execution-limit` | integer `0..99` | self-repair rounds per run (floor: `PW_MAX_SELF_REPAIR`) |
| `max-parallel` | integer `1..99` | concurrent executors at `/pw-execute` |
| `produced-by` | a provider from `PW_PROVIDERS` (see `global show`) | default executor provider for new task pins |
| `ai-review` | `<surface>=<mode>` pairs or `all=<mode>` (+ named overrides); surfaces `context`·`analysis`·`plan`·`task-plan`·`task-exec`·`ship`·`rfc`·`close`; modes `advisory`·`auto` | review OUTCOME per surface: `advisory` = findings + a human still signs off (default); `auto` may self-sign a genuinely clean managed pass (the removed `off` reads as advisory; persist with `ensure`) |
| `review-trigger` | `<surface>=<value>` pairs or `all=<value>`; values `manual`·`completion` | WHEN a pass starts: `manual` (only an explicit `/pw-review … ai`, default) or `completion` (also after a succeeded producing command's verification); `completion` never disables explicit requests |
| `review-repair` | `<surface>=<value>` pairs or `all=<value>`; values `manual`·`bounded` | whether a completion review may run the bounded repair cycle (`review → repair → verify → fresh review`); `manual` = findings stop for me (default) |
| `review-rounds` | integer `1..3` | total reviewer passes in a bounded cycle (default `3` — at most two intervening verified repairs) |
| `ai-model` | `<role>=<provider>:<model>` or `<role>=—` pairs; roles `researcher`·`analyst`·`writer-task`·`reviewer`·`verifier` | spawn-lane model rows; `—` = provider/session default; values are validated live (allowlist + catalog + scope) at write time |
| `pin` | `<T0n>=<provider>:<model>` or `<T0n>=—` pairs | per-task executor pins; written to **both holders** (task-file `Execute with:` + PLAN cell) by one propagator, so gate/audit never see drift; same live validation at write time |
| `rfc-target` | a doc ref/URL | where `/pw-rfc` publishes |

Keys that are **not settable** (facts the flows derive — `set` refuses them and names the owning
command): `status` (phase moves: `/pw-status`), `adopted` (`/pw-adopt`), `base-branches` +
`landing-units` (`/pw-breakdown`). *Result acceptance* is likewise not config — it is the human
workflow gate (`task-accept`).

The operators:

- **`/pw-config <slug> show [--json]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-config.sh project show <slug> [--json]` —
  every axis (config *and* state/data) as `key | kind | stored | source | effective-floor`, plus
  the footer listing the settable keys and their value shapes. Read-only. This is also what to run
  when I just say `/pw-config <slug>` with no operator.
- **`/pw-config <slug> get <key>`** → `…/pw-config.sh project get <slug> <key>` — one key's stored
  value, or `(unset — effective: <floor>)`.
- **`/pw-config <slug> set <key> <value…>`** → `…/pw-config.sh project set <slug> <key> <value…>` —
  the validated write, per-key values: `routing`∈`auto|subagent|headless` (headless = strict
  binding) · `execution-limit`∈int `0..99` · `max-parallel`∈int `1..99` · `produced-by`∈ an enabled
  provider (`global show`) · `ai-review` = `surface=mode` pairs (surfaces
  `context|analysis|plan|task-plan|task-exec|ship|rfc|close`, modes `advisory|auto`; `all=<mode>`
  expands over every surface with named overrides winning regardless of argument order) ·
  `review-trigger` / `review-repair` = `surface=value` pairs (same `all=` expansion; trigger
  values `manual|completion`, repair values `manual|bounded`) ·
  `review-rounds` = one integer `1..3` · `ai-model` = `role=value` pairs (roles
  `researcher|analyst|writer-task|reviewer|verifier`, value `provider:model` or `—`) ·
  `pin` = `T0n=value` pairs (value `provider:model` or `—` to clear; each pin lands in BOTH
  holders — task-file `Execute with:` and the PLAN cell — via the single propagator) ·
  `rfc-target` = a doc ref. The pair-taking keys accept **batch pairs** (`plan=auto task-exec=auto`,
  `review-trigger all=completion ship=manual`, `T01=kilo:prov/m T02=claude:sonnet`):
  every pair is validated first and ANY illegal pair refuses the whole call with nothing written;
  a good batch is one line-update + one LOG line. A value that can't bind (bad enum, provider not
  enabled, model not in the live catalog / out of the configured API-provider scope) is refused
  here, at write time — not discovered at spawn time. The removed `off`/`both` values are refused
  with the replacement (`off` → advisory + `review-trigger`; `both` → `completion`).
- **`/pw-config <slug> ensure`** → `…/pw-config.sh project ensure <slug>` — inserts any missing
  dashboard config lines (`AI Models:`, `AI Review:`, `Review Trigger:`, `Review Repair:`,
  `Review Budget:`) with explicit defaults, and persists the legacy-`off` → `advisory` migration
  in the AI Review line; idempotent.
- **`/pw-config global show`** → `…/pw-config.sh global show` — the effective machine floors
  (providers, API-provider scopes, model allowlists, route default, repair budgets, RFC backend,
  and the **request-review frame + generation prompts** — each effective path plus
  `default`/`custom` source).
  Read-only by design: `pw.config.sh` is the human-owned floor file — there is no `global set`.
- **`/pw-config model-check <provider> <model-id>`** → `…/pw-config.sh model-check <provider> <model-id>` —
  the permission oracle (empty allowlist = all allowed); handy for probing a pin before setting it.

**This is the whole configuration domain.** It used to hang off `/pw-review` as a sub-verb —
reviewing is not configuring; `/pw-review` now only reviews. View what each axis means in
docs/REVIEW.md (AI-assisted review) and docs/EXECUTION.md (§Spawning phase work, routing ladder);
the key table above is also in docs/REFERENCE.md.

Never change the dashboard `Status:` line from here — phase moves are `/pw-status`.
