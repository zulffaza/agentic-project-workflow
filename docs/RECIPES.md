# Command recipes

[README](../README.md) · [Walkthrough](WALKTHROUGH.md) · [Reference](REFERENCE.md)

Find your task below, then copy the command into your agent session.
Replace `delivery-note`, repository names, task IDs, and paths with your actual values.
Paths in review commands are relative to the project directory. Input file names are relative to `context/`.
In syntax descriptions, `<value>` means required and `[value]` means optional. Do not type those brackets.

## Choose a recipe

| You want to… | Jump to |
|---|---|
| Start or orient | [Next command](#find-what-to-do-next) · [Context or adoption](#add-context-or-continue-existing-work) |
| Review or verify | [Feedback and approval](#record-feedback-answers-and-approval) · [AI review](#use-ai-review-with-human-approval) · [Independent verification](#get-an-independent-verification) |
| Run tasks | [Resume or waves](#resume-or-limit-execution) · [Models and concurrency](#change-models-or-concurrency) |
| Publish and maintain branches | [Ship, comments, sync](#publish-handle-comments-or-refresh-branches) · [Ask for review](#ask-teammates-to-review-the-open-mrs) · [Stacked MRs](#inspect-stacked-mrs) |
| Recover or finish | [Reopen a phase](#recover-or-reopen-a-phase) · [Update guidance](#refresh-old-project-guidance-after-a-workflow-update) · [Accept and close](#accept-and-close) |

## Find what to do next

```text
/pw-help
/pw-help project delivery-note
/pw-help command pw-execute delivery-note
/pw-help find acceptance
/pw-status delivery-note
/pw-status --all
```

Help lists commands, explains arguments, or suggests next steps from current project state.
Status shows the phase, task progress, and blockers. Both only read state. Add `--all` for a
one-table overview of every project under the projects root (`--attention` keeps only rows
that need inspection; `--json` prints a machine-readable object).

## Add context or continue existing work

For an existing project, let the agent draft the context from one brief paragraph:

```text
/pw-context delivery-note prepare Customers can save and view an optional delivery note on an order. Existing orders must remain valid. storefront and order-service are likely related. Changing order status and payment behavior is out of scope.
```

Prerequisites: the project exists and is still in the context phase.
The agent drafts `context/REQUIREMENTS.md`, registers inputs, and proposes repository rows from your intent.
It asks before resolving a consequential ambiguity, marks suggestions as proposals, and stops before analysis.
Expected files: `context/REQUIREMENTS.md`, one provenance row per input, and the "Repos in scope" rows.
Open questions stay listed in the brief; answer them and run `prepare` again to refine it.
When the draft is usable, continue with `/pw-analyze delivery-note`.
Running `prepare` again updates its own rows in place; it never duplicates them.

The manual path builds the same files by hand. `req-init` preserves an existing brief.
`add-input` records provenance; it does not write the source file:

```text
/pw-context delivery-note req-init
/pw-context delivery-note add-input --file REQUIREMENTS.md --what Delivery note requirements --source Product brief from me --trust Approved scope
/pw-context delivery-note add-repo order-service main Store the optional delivery note
```

Either path reaches analysis. Registration alone creates a table row; preparation creates or edits the brief and any saved source excerpts.

For a project research pass before analysis:

```text
/pw-research delivery-note --context Identify compatibility risks before analysis
```

Ask explicitly to persist its evidence pack if you need it saved for later analysis.
For one question without a project:

```text
/pw-research "What compatibility checks does an optional API field need?"
```

To continue a branch with an existing MR, use your actual MR URL:

```text
/pw-adopt <slug> <repo> <branch> <mr-url>
```

Add trailing `review` to service that MR's review directly. It requires an MR URL.
See [adoption](ADOPTION.md) for multiple branches and mixed projects.

## Record feedback, answers, and approval

Create reviews for exactly the artifacts you select:

```text
/pw-review delivery-note init analysis/delivery-note.md task/PLAN.md
```

Each artifact must already exist. `init-all` instead creates missing reviews for the current phase only.
Adding feedback and applying it are separate actions:

```text
/pw-review delivery-note item task/review/PLAN.review.md --section Verification --text Cover orders with no note
/pw-review delivery-note task/review/PLAN.review.md
```

| Parameter | Meaning in this example |
|---|---|
| `--section Verification` | The heading or anchor in `task/PLAN.md` that needs attention |
| `--text Cover orders with no note` | Your requested change |

Both values can contain spaces and continue until the next flag or the end of the command.
The flags belong to `item`; it records feedback. The next command applies only PLAN's review.
`/pw-review delivery-note plan` instead selects all reviews in `task/review/`, including individual task reviews.
See [review scope selection](REVIEW.md#apply-feedback-to-the-scope-you-choose).

The shorter form accepts a single section token:

```text
/pw-review delivery-note item analysis/review/delivery-note.review.md §3 Check existing consumers
/pw-review delivery-note answer analysis/review/delivery-note.review.md Q0 Use the service-first approach
/pw-review delivery-note analysis
```

Use an existing question ID. `answer` records your response; the apply pass incorporates it.
After you inspect the revised artifact and resolve open feedback, record your approval:

```text
/pw-review delivery-note signoff task/review/PLAN.review.md approved
```

Other decisions are `changes-requested` and `in-review`. Approval stays attributed to you.
A normal review pass applies feedback; it does not infer your approval from resolved items.
To apply feedback to several tasks in one invocation:

```text
/pw-review delivery-note T01 T02
```

## Resume or limit execution

| You want to… | Command | Result |
|---|---|---|
| Run the remaining plan | `/pw-execute delivery-note` | Continue through ready tasks and their dependencies |
| Stop after the current ready group | `/pw-execute delivery-note --wave` | Report a checkpoint and the next ready tasks |
| Re-run only selected tasks | `/pw-execute delivery-note T02` | Execute the selected scope and stop |

Use the same commands after an interrupted session. Current PLAN approval still applies.
Already completed tasks stay complete in a full resume. Explicit task selection can re-run a completed task.

## Change models or concurrency

Inspect project values and machine settings:

```text
/pw-config delivery-note show
/pw-config global show
```

Set two concurrent executors:

```text
/pw-config delivery-note set max-parallel 2
```

Pin a task to an enabled provider and a model from its current catalog:

```text
/pw-config <slug> set pin T02=<provider>:<model-id>
```

This updates both the task and its PLAN row. A batch validates every pair before writing:

```text
/pw-config <slug> set pin T01=<provider>:<model-id> T02=<provider>:<model-id>
```

Executor pins apply to individual tasks. To choose a model for a project role instead:

```text
/pw-config <slug> set ai-model reviewer=<provider>:<model-id>
```

Use an enabled provider and a valid model ID. Project roles are `researcher`, `analyst`, `writer-task`, `reviewer`, and `verifier`.
There is no project executor role setting; use task pins for execution.
Clear a task pin with `pin T02=—`, or a role override with `ai-model reviewer=—`.

`model-check` checks permission against the allowlist. Setting a pin also checks availability and provider scope.
See [config values](REFERENCE.md#what-you-can-update-per-project-pw-config) and [execution](EXECUTION.md) for routing details.

## Use AI review with human approval

Advisory is the default outcome, and nothing starts by itself (`review-trigger` is `manual`).
Request a pass after each artifact exists:

```text
/pw-review delivery-note ai analysis
/pw-review delivery-note ai plan
```

Advisory mode records findings and leaves approval to you. Use the normal review command to apply
findings, inspect the changes, then sign off. Outcome modes are `advisory` and `auto`; auto can
approve a clean MANAGED pass under additional safeguards. To let a surface review run right after
its producing command, set `review-trigger <surface>=completion`; to let a completion review also
repair and re-review within the budget, set `review-repair <surface>=bounded` (budget:
`review-rounds`). To review in a separate session instead, freeze a packet with
`/pw-review <scope> prepare …` and import the returned JSON with `import --report …` — imports are
advisory only.
See [AI-assisted review](REVIEW.md#3-ai-assisted-review-optional-advisory--manual-by-default) before enabling auto.

## Publish, handle comments, or refresh branches

```text
/pw-ship delivery-note T01
/pw-ship delivery-note T01 comments
/pw-sync delivery-note
```

Ship publishes selected verified work. Comments mode can fix code, push, and reply on the MR.
Sync merges updated target branches into open MR branches, verifies the changes, and pushes them.
These commands change remote state. CI monitoring runs by default.
`--skip-build-check` skips monitoring during ship or comments mode; it is not a dry run.
If a push succeeds but the description remains pending, follow [description recovery](TROUBLESHOOTING.md#changes-were-pushed-but-the-mr-description-update-is-pending).

## Ask teammates to review the open MRs

`request-review` is read-only. It never pushes, comments, or waits on CI. It builds one copyable
message with one entry per unique open MR — title, link, target branch, current CI status, and the
assigned reviewers — and prints it after a short selection recap.

```text
/pw-ship delivery-note request-review
/pw-ship delivery-note request-review T01 T03 --to "Andi, Sari"
/pw-ship delivery-note request-review T02 --no-reviewers
```

With no selector (or `all`), every unique open MR is included; tasks without an MR and
merged/closed MRs appear as exclusions in the recap. Naming task IDs selects exactly those tasks —
a missing, merged, closed, or conflicting MR link then stops the run so you can fix the scope.

Options add writing help: `--to <names>` sets the greeting, `--summary` adds a short global
summary, `--mr-summary` adds one short summary per MR, and `--note` adds up to three reviewer
hints. With any of these on, the command first returns the deterministic message plus a short
evidence packet and the effective writing prompts; you then author the requested text (the
wording is yours or your agent's, the facts always come from the evidence) and re-run with
`--prose <file>` to get the final message.
If the text is too long or a section cannot be written, the deterministic message still stands.

The message layout and the writing prompts are editable, no reinstall needed. The defaults live
under `user/` in your workflow install: `user/templates/review-request.md` (layout),
`user/prompts/review-request-summary.md` (summary prose), and
`user/prompts/review-request-note.md` (note prose). Edit a default in place, or set one of the
three path settings in `pw.config.sh` to use a different file — see the
[review-request file settings](REFERENCE.md#review-request-files-machine-settings-in-pwconfigsh).
`user/` is git-ignored, so local customizations stay out of ordinary commits and pushes.
Recovery when a file is missing or the message looks wrong:
[the review-request message](TROUBLESHOOTING.md#the-review-request-message-looks-wrong-or-the-frame-file-is-missing).

## Inspect stacked MRs

A stack lets one task inherit another task's code in the same repository.
Preview the topology and health:

```text
/pw-ship delivery-note stack
```

For existing manually stacked MRs, preview the import before applying it:

```text
/pw-ship delivery-note stack adopt
/pw-ship delivery-note stack adopt --apply
```

The preview is read-only. `--apply` records the import after confirmation.
Publish parents before children. A scheduling dependency alone does not form a stack.
See [stack lifecycle and blocked promotion](WORKFLOW.md#stacked-mrs) before changing existing stacks.

## Get an independent verification

```text
/pw-verify <project-directory>/task/T02.md
```

Give the verifier the actual task-file path or a repository/worktree target.
It runs checks and reports evidence. It does not fix code or update MRs.

## Recover or reopen a phase

```text
/pw-doctor
/pw-doctor --project delivery-note
```

The first checks installation consistency. The second checks project consistency.
Add `--fix` to request supported deterministic repairs; unresolved findings still need action.
If commands are unavailable, use [onboarding recovery](../ONBOARDING.md#troubleshooting--pw-doctor).

To revisit an earlier approach:

```text
/pw-status delivery-note rewind analysis
```

Follow the prompted review and reapproval steps. Downstream artifacts remain on disk.

To redo requirements and context:

```text
/pw-status delivery-note rewind context
```

Context has no review file of its own. First record the reason on the existing analysis review, and on the PLAN review when one exists.
Those entries reopen the affected approvals through the normal review flow.
After the rewind, redo the context (`/pw-context delivery-note prepare <brief>` or the manual row operators), then run `/pw-analyze delivery-note` again.
Revised work continues only after the analysis and plan approvals are recorded again.
See [troubleshooting](TROUBLESHOOTING.md) for failures, stalled runs, and stack blockers.

## Refresh old project guidance after a workflow update

Use this when an existing project's instructions mention internal scripts or outdated manual setup steps.
Updating the bundle supplies new templates for new projects. It does not replace the guidance copied into an existing project.

Preview recognized guidance changes for the project you choose:

```text
/pw-doctor --project delivery-note --guidance
```

The preview writes nothing. It lists matching files, before/after text, and skipped targets.
For example, an old requirements paragraph can change from manual copying to `/pw-context <slug> prepare <brief>`.
The repair also recognizes legacy hints in `analysis/review/` and `task/review/`, plus archive banners in matching review directories.
Examples of the updated guidance:

| Legacy instruction | Updated guidance |
|---|---|
| Create every missing review in the project | `init-all` covers the current phase; use `init` for named existing artifacts |
| Run a script to refresh the review contents table | Review writes refresh the table automatically |
| Run a script to archive resolved feedback | The review pass archives resolved items when needed |
| Reopen a phase through a status script | Use `/pw-status <slug> rewind <phase>` |
| Record approval through a script | Use `/pw-review <slug> signoff <review-path> approved` after your review |

These replacements update instructions. They do not apply feedback, archive items, reopen a phase, or record approval.
Read the replacements before applying them to that same project:

```text
/pw-doctor --project delivery-note --guidance --apply
/pw-doctor --project delivery-note --guidance
```

The first command applies recognized replacements. The second previews again to confirm zero remaining recognized replacements.
Already updated, customized, or absent guidance can appear as skipped. Leave customized text intact and review it separately if needed.
A zero count does not prove that every custom instruction is current.

This command repairs recognized workflow guidance. It preserves requirements, provenance rows, review items, approval history, and custom sections outside those matches.
It also leaves the dashboard phase, MR records, and stack state unchanged. It does not contact a forge.

For health findings, run `/pw-doctor --project delivery-note` separately.
Use `--fix` for its supported health repairs. `--guidance` cannot combine with `--fix`, and `--apply` requires `--guidance`.

## Accept and close

Ask in chat: `Accept T01 and T02 in delivery-note; I reviewed their diffs and verification results.`
Then confirm task status and close:

```text
/pw-status delivery-note
/pw-close delivery-note
```

Close requires accepted tasks. Acceptance does not merge MRs.
For pre-reviewed plans, `/pw-execute <slug> --acceptance auto` opts into clean result acceptance for that run.
Adding `--then-ship` requests chained publication, with push confirmation still required.
Read [clean execution](EXECUTION.md#opt-in-clean-execution-pre-reviewed-plans) before using these flags.
