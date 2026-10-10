# Reference: commands, settings, and files

[README](../README.md) · [Recipes](RECIPES.md) · [Workflow](WORKFLOW.md)

Use this page to look up syntax. Use the [walkthrough](WALKTHROUGH.md) to follow a complete project.
Run `/pw-help command <name> [<slug>]` for the current command's detailed usage.
Commands belong in your agent session. Setup commands belong in a terminal.

`<slug>` is the project identifier: lowercase letters, digits, and hyphens, starting with a letter or digit (for example, `delivery-note`).
`<value>` is required; `[value]` is optional. Do not type the brackets.
Review paths are project-relative. Input file names are relative to `context/`.
Task IDs are `T01`, `T02`, etc. Multiple task IDs use spaces.

<a id="slash-commands--the-generator-one-source-of-truth"></a>
## Command syntax

### Start and provide context

| Command | Purpose |
|---|---|
| `/pw-new <slug>` | Create a fresh project |
| `/pw-adopt <slug> <repo> <branch> [mr-url] [review]` | Continue existing work; trailing `review` requires an MR |
| `/pw-context <slug> prepare [brief]` | Let the agent draft the context from your intent: requirements brief, inputs, repository guesses; stops before analysis |
| `/pw-context <slug> req-init` | Create an optional requirements brief, preserving an existing file |
| `/pw-context <slug> add-input --file <f> --what <description> --source <source> [--trust <notes>]` | Register one input's provenance |
| `/pw-context <slug> add-repo <repo> <base> <why>` | Register repository scope |
| `/pw-research "<question>"` | Answer one question without a project |
| `/pw-research <slug> --context [focus]` | Check the project's context against sources and code |
| `/pw-analyze <slug> [focus]` | Produce analysis from the context |
| `/pw-breakdown <slug>` | Turn approved analysis into PLAN and tasks |

### Review and approve

| Command | Purpose |
|---|---|
| `/pw-review <slug> [phase\|task-ids\|review-path]` | Apply recorded feedback; default scope follows the current phase |
| `/pw-review <slug> init <artifact-path> [artifact-path…]` | Create reviews for exactly the named existing artifacts |
| `/pw-review <slug> init-all` | Create missing reviews for the current phase only |
| `/pw-review <slug> item <review-path> --section <section words> --text <ask>` | Record feedback with a heading or anchor and your requested change |
| `/pw-review <slug> item <review-path> <section-token> <ask>` | Short form for a single section token, such as `§4` |
| `/pw-review <slug> answer <review-path> <Qid> <answer>` | Record an answer to an existing question |
| `/pw-review <slug> signoff <review-path> <decision>` | Record your `approved`, `changes-requested`, or `in-review` decision |
| `/pw-review <slug> ai [phase\|task-ids\|review-path]` | Request a fresh AI pass for an enabled review mode |

`init` takes the artifact path, such as `task/PLAN.md`. `item`, `answer`, and `signoff` take its review path.
For `item`:

- `--section` identifies a heading or anchor in the artifact being reviewed.
- `--text` is the feedback you want applied.
- Both values can contain spaces; each ends at the next flag or the end of the command. No quoting is needed.

The flags record feedback. Apply it afterward with `/pw-review <slug> <review-path>` for one file.
`plan` (or `task`) instead selects the `task/review/` directory, including individual task reviews.
See [review scope selection](REVIEW.md#apply-feedback-to-the-scope-you-choose).
An answer alone does not resolve its question.
See [review](REVIEW.md) for scope, gate transitions, and AI approval safeguards.

### Execute and publish

| Command | Purpose |
|---|---|
| `/pw-execute <slug> [task-ids]` | Execute selected tasks, or resume the remaining plan |
| `/pw-execute <slug> --wave` | Run only the tasks ready at this checkpoint |
| `/pw-execute <slug> T02 with <model-or-agent>` | Override execution choice for the selected task |
| `/pw-execute <slug> --acceptance <manual\|auto>` | Override result acceptance for one run |
| `/pw-execute <slug> --then-ship` | Request shipping after execution, with push confirmation |
| `/pw-ship <slug> [task-ids] [--skip-build-check]` | Push verified branches, open MRs, and monitor CI |
| `/pw-ship <slug> [task-ids] comments [--skip-build-check]` | Handle MR feedback, including fixes, pushes, and replies |
| `/pw-ship <slug> request-review [all\|task-ids] [--to <names>] [--summary] [--mr-summary] [--note] [--no-reviewers] [--prose <file>]` | Read-only: one copyable teammate review request for the open MRs |
| `/pw-ship <slug> stack` | Preview stack topology and health without writes |
| `/pw-ship <slug> stack adopt [task-ids] [--apply]` | Preview an existing stack import; `--apply` records it |
| `/pw-sync <slug> [task-ids]` | Refresh open MR branches against changed targets, verify, and push |
| `/pw-verify <repo-ref\|worktree-path\|task-path> [--commit <sha>] [note]` | Independently verify a result without fixing it |
| `/pw-close <slug>` | Check acceptance, record learnings, and clean eligible worktrees |

`--skip-build-check` skips the ship CI monitor. It still publishes changes.
On local task review, the same flag skips the repair verification loop; the recap must identify the unchecked result.
Task acceptance is an explicit human request in chat, unless clean automatic acceptance is enabled.
It is separate from PLAN approval and MR merging.

### Inspect, configure, and recover

| Command | Purpose |
|---|---|
| `/pw-help [overview]` | List commands |
| `/pw-help command <name> [slug]` | Explain one command with examples |
| `/pw-help project <slug> [name]` | Show commands that apply to the project now |
| `/pw-help workflow` | Show the phase sequence and gates |
| `/pw-help find <term>` | Search command and user documentation |
| `/pw-status <slug>` | Show project progress and blockers |
| `/pw-status <slug> rewind <phase>` | Reopen an earlier phase with a review trail |
| `/pw-doctor [--fix]` | Check or repair installation consistency |
| `/pw-doctor --project <slug> [--fix]` | Check or repair supported project consistency findings |
| `/pw-doctor --project <slug> --guidance` | Preview recognized guidance updates in an existing project |
| `/pw-doctor --project <slug> --guidance --apply` | Apply the selected project's recognized guidance updates |
| `/pw-config <slug> [show]` | Show project settings and their sources |
| `/pw-config <slug> get <key>` | Read one value |
| `/pw-config <slug> set <key> <value…>` | Validate and change a project setting |
| `/pw-config <slug> ensure` | Add missing config fields with defaults |
| `/pw-config global show` | Read machine settings; no project slug |
| `/pw-config model-check <provider> <model-id>` | Check model permission against the allowlist; no project slug |

Guidance preview writes nothing. Applying it repairs recognized prose, preserving project state and custom content outside the matches.
Health repair (`--fix`) and guidance repair are separate modes. See the [preview/apply recipe](RECIPES.md#refresh-old-project-guidance-after-a-workflow-update).

Model permission does not prove live availability. Pin writes also validate the catalog and provider scope.
For optional RFCs, use `/pw-rfc <slug> [--target <ref>]`, `/pw-rfc <slug> milestone`, or `/pw-rfc <slug> comments`.
The [RFC guide](RFC.md) explains publication, targets, and the local comment loop.

### What you can update per project (`/pw-config`)

| Key | Accepted values | Changes |
|---|---|---|
| `routing` | `auto`, `subagent`, `headless` | Default task route; headless requires strict model binding |
| `execution-limit` | Integer `0..99`, subject to the machine floor | Self-repair budget |
| `max-parallel` | Integer `1..99` | Concurrent executors |
| `produced-by` | An enabled provider | Default provider for new executor pins |
| `ai-review` | `surface=mode` pairs or `all=mode` (+ named overrides) | Review OUTCOME per surface — `advisory` (default; a legacy `off` reads as advisory) or `auto` (guarded self-approval of a clean managed pass) |
| `review-trigger` | `surface=value` pairs or `all=value` | WHEN a pass starts — `manual` (default) or `completion` (also after a succeeded producing command's verification) |
| `review-repair` | `surface=value` pairs or `all=value` | Whether a completion review may repair+re-review — `manual` (default) or `bounded` (within the budget) |
| `review-rounds` | Integer `1..3` | Total reviewer passes in a bounded cycle (default `3`; at most two intervening repairs) |
| `ai-model` | `role=provider:model` or `role=—` pairs | Model for a workflow role; `—` clears the override |
| `pin` | `T01=provider:model` or `T01=—` pairs | Executor model in both task and PLAN |
| `rfc-target` | A document reference or URL | RFC destination |

Review surfaces: `context`, `analysis`, `plan`, `task-plan`, `task-exec`, `ship`, `rfc`, `close`.
Review outcome modes: `advisory`, `auto`. Default is `advisory` (nothing starts by itself —
`review-trigger` is `manual`).
For the three per-surface axes, `all=<value>` sets every surface and explicitly named surfaces
override the baseline regardless of argument order. `off` writes are refused with the replacement
named (`off` was the pre-migration outcome value — reads normalize it to `advisory`).
Model roles: `researcher`, `analyst`, `writer-task`, `reviewer`, `verifier`.

For `ai-review`/`review-trigger`/`review-repair`, `ai-model`, and `pin`, a batch validates every
pair before writing any value:

```text
/pw-config delivery-note set ai-review all=auto context=advisory
/pw-config delivery-note set review-trigger all=completion ship=manual
```

`show` also lists facts owned by other commands. `set` cannot change project status, adopted work, base branches, or landing units.
Change machine settings in `pw.config.sh`. See [onboarding](../ONBOARDING.md) and [recipes](RECIPES.md#change-models-or-concurrency).

### Review-request files (machine settings in `pw.config.sh`)

Three optional settings point the review-request message at your files:

| What you put in config | Which file is used |
|---|---|
| No setting | The editable default file under `user/` in your workflow install. |
| Empty string `""` | The same editable default file. This does not disable the feature. |
| A real file path | That file. Absolute paths stay absolute; relative paths start at the install root. |

| Setting | Default file |
|---|---|
| `PW_REVIEW_REQUEST_TEMPLATE_FILE` | `user/templates/review-request.md` — the message layout |
| `PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE` | `user/prompts/review-request-summary.md` — writing instructions for `--summary` and `--mr-summary` |
| `PW_REVIEW_REQUEST_NOTE_PROMPT_FILE` | `user/prompts/review-request-note.md` — writing instructions for `--note` |

You can edit a default file in place, or set a path to use another file. The shipped seed supplies
the initial content; upgrades and repair preserve existing user files. The AI flags
(`--summary`, `--mr-summary`, `--note`) enable prose generation independently of these settings.
The prompts are read as plain text on each generation pass, so edits take effect on the next run.
An invalid template path stops the message with an error; an invalid prompt path omits that
section from the generated prose and reports the path outside the message. `/pw-doctor` checks all
three effective files, and `/pw-doctor --fix` seeds only missing defaults. See the
[ask-for-review recipe](RECIPES.md#ask-teammates-to-review-the-open-mrs) for customization.

## Project anatomy (a scaffolded `<slug>/`)

The project lives at `$PW_PROJECTS/<slug>/`.

| File or directory | What you read or provide |
|---|---|
| `README.md` | Dashboard with phase, task/MR links, and settings |
| `LOG.md` | Recorded actions and timestamps |
| `context/INDEX.md` | Input provenance and repository scope |
| `context/REQUIREMENTS.md` | Your optional requirements brief |
| `analysis/<topic>.md` | Proposed approach, evidence, and open questions |
| `analysis/review/<topic>.review.md` | Analysis feedback, answers, and approval |
| `task/PLAN.md` | Task dependencies, execution strategy, and repository manifest |
| `task/T01.md`, etc. | Task steps, verification checks, and actual results |
| `task/review/PLAN.review.md` | Approval that gates execution |
| `task/review/T01.review.md`, etc. | Optional task-plan or task-result review |
| `worktree/<repo>/<task-id>-<name>/` | Task checkout; execution logs also live under `worktree/` |
| `REVIEWER-NOTES.md` | AI review reasoning, when AI review is used |
| `rfc/` | Optional RFC content, metadata, and review records |

## Who fills what (legend)

You supply requirements, source material, review feedback, answers, and approval decisions.
Use context and review commands for structured records. Ask the agent explicitly to accept task results.
Agents maintain analysis, PLAN, task results, dashboard tables, and the audit log.
Commands maintain project phase and configuration values. Use rewind to move back a phase.

## Conventions (the contract every agent follows)

Task IDs stay stable and use zero padding. Dependencies state which tasks must finish first.
A task's base branch selects its starting point. A stacked task inherits its parent's verified commit and targets the parent's branch.
Fresh task branches use `agent/<slug>/<task-id>-<name>`. Adoption continues the existing branch.
Every task needs runnable verification checks and expected results. Read actual output in `## Result` before acceptance.

## Bundle layout (this repo)

`$PW_HOME` is the workflow bundle. `$PW_PROJECTS` is its parent, where project records live.
`$PW_REPOS` is the repository root, two levels above the bundle by default. Setup can override it.

The bundle contains `README.md`, `ONBOARDING.md`, human guides in `docs/`, project templates in `template/`, and your `pw.config.sh`.
Setup writes `pw-env.sh`. Run `./bootstrap.sh` to install and `./offboard.sh` to preview uninstall.
Installed provider files are generated copies. Repair drift through `/pw-doctor --fix`.
