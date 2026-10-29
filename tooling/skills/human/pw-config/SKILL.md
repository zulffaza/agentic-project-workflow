---
name: pw-config
description: The one configuration surface — validated per-project knobs, creation-time global project defaults in pw.config.sh, and model permission/capability checks
args: "[show | get | set | ensure | materialize] --project <project-slug> … | global [show | get | set | unset] … | models [--provider <provider>]… | agent-model --provider <provider> --agent <name> | model-check --provider <provider> --model <model-id> [--variant <v>] [--reasoning <v>] [--effort <v>] [--json]"
scope: mixed
scope-forms: "global=global, default=project, show=project, get=project, set=project, ensure=project, materialize=project, global show=global, global get=global, global set=global, global unset=global, models=global, agent-model=global, agent-model-set=global, agent-model-unset=global, agent-models=global, spawn-args=global, model-check=global, model-resolve=global, ai-model=project, ai-review=project, review-trigger=project, review-repair=project, review-rounds=project"
args-global: "global show [--json] | global get --key <key> [--provider <p> --agent <name>] [--json] | global set --key <key> [--value <v> | --set <member=value>]… | global unset --key <key> [--provider <p> --agent <name>] | models [--provider <p>]… [--search <term>] [--limit <n>] | agent-model --provider <p> --agent <name> | agent-model-set --provider <p> --agent <name> --value <spec> | agent-models | spawn-args --provider <p> --agent <name> | model-check --provider <provider> --model <model-id> [--tuning] [--json]"
args-project: "show --project <project-slug> [--json] | get --project <project-slug> --key <key> [--json] | set --project <project-slug> --key <key> [--value <v> | --set <member=value>]… [--variant <v> --reasoning <v> --effort <v>] | ensure --project <project-slug> | materialize --project <project-slug>"
---

**Load shared guidance first.** Read the `pw-orchestration` skill's common rules
(`references/common.md`) before acting: authorization, operation scope, helper ownership, and
reporting. Load only the phase-specific references this operation needs. A read-only operation
must not run execution or mutation procedures.
Arguments: {{ARGS}}. Project dir: `{{PW_PROJECTS}}/<slug>`.

**This command is a mechanical mapping (C3): parse my words into one script call below, run it,
and show its output.** Configuration lives in the project's own docs (dashboard/PLAN/task files/
RFC META) — this command is the *validated lens* over them; there is no separate config file, and
you never hand-edit those lines — the script owns them, validates every write, and logs it to
`LOG.md`. When I ask "what can I change?", run **`show`** — it lists every key with its kind and
where it is stored.

**Named-argument grammar:** operator words first; every value named. The project is always
`--project <slug>`. The machine-side operators (`global show`, `model-check`) take no project.
When I just say `/pw-config --project <slug>` with no operator, run `show`.

The keys you can `set`, and their legal values (the same list `show` prints as its footer):

| key | settable to | meaning of the value |
|---|---|---|
| `routing` | `auto` · `subagent` · `headless` | default route for every task; `headless` = **strict** model binding, no silent downgrade |
| `execution-limit` | integer `0..99` | self-repair rounds per run (floor: `PW_MAX_SELF_REPAIR`) |
| `max-parallel` | integer `1..99` | concurrent executors at `/pw-execute`, and concurrent MR comment fixers at `/pw-ship comments` |
| `produced-by` | a provider from `PW_PROVIDERS` (see `global show`) | default executor provider for new task pins |
| `ai-review` | `<surface>=<mode>` pairs or `all=<mode>` (+ named overrides); surfaces `context`·`analysis`·`plan`·`task-plan`·`task-exec`·`ship`·`rfc`·`close`; modes `advisory|auto` | review OUTCOME per surface: `advisory` = findings + a human still signs off (default); `auto` may self-sign a genuinely clean managed pass (the removed `off` reads as advisory; persist with `ensure`) |
| `review-trigger` | `<surface>=<value>` pairs or `all=<value>`; values `manual|completion` | WHEN a pass starts: `manual` (only an explicit `/pw-review … ai`, default) or `completion` (also after a succeeded producing command's verification); `completion` never disables explicit requests |
| `review-repair` | `<surface>=<value>` pairs or `all=<value>`; values `manual`·`bounded` | whether a completion review may run the bounded repair cycle (`review → repair → verify → fresh review`); `manual` = findings stop for me (default) |
| `review-rounds` | integer `1..3` | total reviewer passes in a bounded cycle (default `3` — at most two intervening verified repairs) |
| `ai-model` | `<role>=<provider>:<model>` or `<role>=—` pairs; roles `researcher`·`analyst`·`writer-task`·`reviewer`·`verifier`·`ship-comment-analyst`·`explorer`; optional `--variant`/`--reasoning`/`--effort` on a ONE-role write | spawn-lane model rows; `—` = provider/session default; model is validated live (allowlist + catalog + scope), tuning against the provider capability table. Unsupported or unverified tuning is refused, never silently dropped. Tuning is read with `get --key ai-model --json`; plain `get` stays `role=model` compatible |
| `pin` | `<T0n>=<provider>:<model>` or `<T0n>=—` pairs | per-task executor pins; written to **both holders** (task-file `Execute with:` + PLAN cell) by one propagator, so gate/audit never see drift; same live validation at write time |
| `rfc-target` | a doc ref/URL | where `/pw-rfc` publishes |

Keys that are **not settable** (facts the flows derive — `set` refuses them and names the owning
command): `status` (phase moves: `/pw-status`), `adopted` (`/pw-adopt`), `base-branches` +
`landing-units` (`/pw-breakdown`). *Result acceptance* is likewise not config — it is the human
workflow gate (`task-accept`).

The operators (operator words first; every value named — `--project <slug>` selects the project):

- **`/pw-config show --project <slug> [--json]`** → `{{PW_HOME}}/tooling/scripts/entities/pw-config.sh show --project <slug> [--json]` —
  every axis (config *and* state/data) as `key | kind | stored | source | effective-floor`, plus
  the footer listing the settable keys and their value shapes. Read-only.
- **`/pw-config get --project <slug> --key <key>`** → `…/pw-config.sh get --project <slug> --key <key>` — one key's stored
  value, or `(unset — effective: <floor>)`.
- **`/pw-config set --project <slug> --key <key> [--value <v> | --set <member=value>]…`** → `…/pw-config.sh set --project <slug> --key <key> …` —
  the validated write, per-key values: `routing`∈`auto|subagent|headless` (headless = strict binding) · `execution-limit`∈int `0..99` · `max-parallel`∈int `1..99` (execute executors and MR comment fixers) · `produced-by`∈ an enabled
  provider (`global show`) · `ai-review` = `surface=mode` pairs (surfaces
  `context|analysis|plan|task-plan|task-exec|ship|rfc|close`, modes `advisory|auto`; `all=<mode>`
  expands over every surface with named overrides winning regardless of argument order) ·
  `review-trigger` / `review-repair` = `surface=value` pairs (same `all=` expansion; trigger
  values `manual|completion`, repair values `manual|bounded`) ·
  `review-rounds` = one integer `1..3` · `ai-model` = `role=value` pairs (roles `researcher|analyst|writer-task|reviewer|verifier|ship-comment-analyst|explorer`, value `provider:model` or `—`) ·
  `pin` = `T0n=value` pairs (value `provider:model` or `—` to clear; each pin lands in BOTH
  holders — task-file `Execute with:` and the PLAN cell — via the single propagator) ·
  `rfc-target` = a doc ref. Scalar keys take **`--value <v>`**; the pair-taking keys take repeated
  **`--set <member=value>`** (`--set plan=auto --set task-exec=auto`,
  `--set all=completion --set ship=manual`, `--set T01=kilo:prov/m --set T02=claude:sonnet`):
  every pair is validated first and ANY illegal pair refuses the whole call with nothing written;
  a good batch is one line-update + one LOG line. A value that can't bind (bad enum, provider not
  enabled, model not in the live catalog / out of the configured API-provider scope) is refused
  here, at write time — not discovered at spawn time. The removed `off`/`both` values are refused
  with the replacement (`off` → advisory + `review-trigger`; `both` → `completion`).
- **`/pw-config ensure --project <slug>`** → `…/pw-config.sh ensure --project <slug>` — inserts any missing
  dashboard config lines (`AI Models:`, `AI Review:`, `Review Trigger:`, `Review Repair:`,
  `Review Budget:`) with explicit defaults, and persists the legacy-`off` → `advisory` migration
  in the AI Review line; idempotent. Reads never write: a `get` of an absent line shows the
  effective defaults with a note — `ensure` (or any `--set`) is the door that persists it.
- **`/pw-config global show`** → `…/pw-config.sh global show` — the effective machine floors
  (providers, API-provider scopes, model allowlists, route default, repair budgets, RFC backend,
  and the **request-review frame + generation prompts** — each effective path plus
  `default`/`custom` source).
  This read form writes nothing. `global set` / `global unset` below are the only managed writers;
  they change one managed block and preserve unrelated shell settings.
- **`/pw-config global show [--json]`** → the machine floors **plus** every inherited project
  default, each with `inherited: yes|no`, destination, effective value, and source. Defaults are
  copied into NEW projects only; a global change never rewrites an existing project.
- **`/pw-config global get --key <key>`** → one inherited default and its source.
- **`/pw-config global set --key <key> …`** → validated write into one managed assignment block in
  `pw.config.sh` (no second config file). Scalars take `--value`; `ai-review`, `review-trigger`,
  `review-repair`, and `ai-model` take `--set` pairs. Unrelated shell settings are preserved and
  the staged file is `bash -n` checked before an atomic replace.
- **`/pw-config global unset --key <key>`** → removes that override, revealing the previous
  assignment or built-in fallback.
- **`/pw-config models [--provider <p>]… [--api-provider <prefix>]… [--search <term>] [--limit <n>] [--all] [--details] [--format table|tsv]`** →
  `…/pw-config.sh models …` — bounded model discovery per provider. Reports the source honestly
  (live catalog, Claude's fixed aliases, unavailable CLI, empty result, unsupported surface) and
  applies API-provider prefix filters locally. No live model request by default.
- **`/pw-config agent-model --provider <p> --agent <name>`** → `…/pw-config.sh agent-model …` —
  read one provider-specific worker default. `agent-model-set` writes one validated cell
  (`--value '<model>[key=value,…]'`, `—` clears), and `agent-model-unset` clears it. These are the
  same operations as `global get/set/unset --key agent-model`. A write validates provider
  membership, the provider prefix, catalog availability, the allowlist, and the tuning capability;
  invalid input leaves the configuration byte-identical.
- **`/pw-config agent-models`** → `…/pw-config.sh agent-models [--provider <p>]… [--json]` — the
  complete provider × canonical-worker matrix with model, parameters, and source.
- **`…/pw-config.sh materialize --project <slug>`** → internal breakdown step: copies the dashboard
  `Project Defaults` seed into a newly created PLAN once. Explicit PLAN values win; the seed is
  never re-read.
- **`/pw-config model-check --provider <provider> --model <model-id> [--variant <v>] [--reasoning <v>] [--effort <v>] [--json]`** → `…/pw-config.sh model-check …` —
  the permission oracle (empty allowlist = all allowed) plus the local, documented tuning
  capability table. With no tuning flags it lists supported variants/reasoning/effort; with flags
  it validates the requested combination. Capability metadata is `unsupported`, `unknown`, or a
  value list — never guessed from another provider. No model request is spent.

**This is the whole configuration domain.** It used to hang off `/pw-review` as a sub-verb —
reviewing is not configuring; `/pw-review` now only reviews. View what each axis means in
`{{PW_HOME}}/docs/REVIEW.md` (AI-assisted review) and `{{PW_HOME}}/docs/EXECUTION.md`
(§Spawning phase work, routing ladder); the key table above is also in `{{PW_HOME}}/docs/REFERENCE.md`.

Never change the dashboard `Status:` line from here — phase moves are `/pw-status rewind --project <slug> --phase <phase>` (or the monotonic forward moves the other commands make).
