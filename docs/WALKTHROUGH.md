# Walkthrough: your first project

[README](../README.md) · [Recipes](RECIPES.md) · [Workflow](WORKFLOW.md)

This fictional example adds an optional delivery note across two repositories.
Commands match the workflow interface. File names, task IDs, and outcomes below are illustrative.
Substitute your actual repositories, base branches, and generated artifact names.

## The scenario

Project `delivery-note` changes `storefront` and `order-service`.
Use a slug with lowercase letters, digits, and hyphens, starting with a letter or digit.
The goal is to save and display a delivery note. Orders without a note must keep working.
Both repositories already exist under your configured repository root, and their base branch is `main`.

[Install first](../ONBOARDING.md) if the commands are unavailable.
Use a terminal for setup and files. Use your agent session for every `/pw-*` command.
In Codex, select the corresponding installed `pw-*` skill.

## Follow the main path

| Checkpoint | Next section |
|---|---|
| Describe the change | [Drop context](#drop-context) |
| Approve the approach | [Analyze](#analyze) · [Review analysis](#review-the-analysis) |
| Approve the task plan | [Break down](#break-down) · [Review PLAN](#review-the-plan-the-hard-gate) |
| Build and publish | [Execute](#execute) · [Ship](#ship) |
| Finish the project | [Accept results](#accept-results) · [Close](#close) |

Individual task-plan review and corrective result review are optional detours.
Run commands one at a time. Inspect the result and resolve any blocker before continuing.

## Drop context

Create the project and an optional requirements brief:

```text
/pw-new delivery-note
/pw-context delivery-note req-init
```

The project appears at `$PW_PROJECTS/delivery-note/`.
`req-init` creates `context/REQUIREMENTS.md`; it does not fill your requirements.
Open that file and write the goal, behavior, exclusions, and completion checks. For example:

```text
Goal: Customers can save and view a delivery note on an order.
Behavior: The note is optional. Existing orders remain valid.
Out of scope: Changing order status or payment behavior.
Completion: Tests cover orders with a note and orders without one.
```

Save any supporting ticket or specification in `context/`, then register each actual input.
The file name below is relative to `context/`. Registering a row does not create the input file.

```text
/pw-context delivery-note add-input --file REQUIREMENTS.md --what Delivery note requirements --source Product brief from me --trust Approved scope
/pw-context delivery-note add-repo storefront main Collect and display the note
/pw-context delivery-note add-repo order-service main Store and return the optional note
```

Expected result: `context/INDEX.md` lists the requirements file and both repositories.
Use actual source details when you add a ticket, document link, or log.

## Analyze

```text
/pw-analyze delivery-note
```

The agent examines the inputs and repository code, then writes analysis and a matching review file.
In this example, the files are `analysis/delivery-note.md` and `analysis/review/delivery-note.review.md`.
Read the analysis for affected surfaces, approach options, compatibility risks, and unanswered questions.
Use the generated paths if your project uses different names.

## Review the analysis

Suppose the review file asks `Q0` about the approach. Answer the existing question:

```text
/pw-review delivery-note answer analysis/review/delivery-note.review.md Q0 Add the optional service field first, then update the storefront
```

Use the question IDs in your actual review file. To request another change, add an item:

```text
/pw-review delivery-note item analysis/review/delivery-note.review.md --section Compatibility risks --text Check orders that have no delivery note
/pw-review delivery-note analysis
```

The first command records feedback. The second applies analysis feedback and incorporates your answers.

| Part of the feedback command | Meaning |
|---|---|
| `delivery-note` | The project slug |
| `item` | Record a new review item |
| `analysis/review/delivery-note.review.md` | Review file receiving the item, relative to the project |
| `--section Compatibility risks` | Heading or anchor in the analysis you want changed; use your actual heading |
| `--text Check orders that have no delivery note` | Your requested change |

`--section` and `--text` belong to the `item` action. Each value continues until the next flag or the end of the command, so multi-word values need no quotes.
See [review feedback parameters](REVIEW.md#add-feedback-with-section-and-text) for the shorter form.
Read the revised analysis and the agent replies. Once questions and review items are resolved, approve it:

```text
/pw-review delivery-note signoff analysis/review/delivery-note.review.md approved
```

`signoff` records your decision. Resolving feedback alone does not record human approval.
For an optional AI pass, use the [advisory review recipe](RECIPES.md#use-ai-review-with-human-approval).

## Break down

```text
/pw-breakdown delivery-note
```

The agent writes `task/PLAN.md` and individual task files. An illustrative plan contains:

| Task | Repository | Work | Dependency |
|---|---|---|---|
| T01 | order-service | Store and return the optional note | None |
| T02 | storefront | Collect and display the note | T01 |

Each task needs concrete steps and a runnable `## Verify` block.
Check the repository, base branch, model choice, dependencies, and expected test results.

## Review the plan (the hard gate)

If the plan misses compatibility tests, record that request and apply it:

```text
/pw-review delivery-note item task/review/PLAN.review.md --section Verification --text Require tests for orders with no note
/pw-review delivery-note task/review/PLAN.review.md
```

The second command applies feedback from that exact review file to `task/PLAN.md`.

You may also see `/pw-review delivery-note plan`:

- `delivery-note` is the project slug.
- `plan` is a **scope selector**, not a file name or an approval decision.
- It selects reviews under `task/review/`, including PLAN and any individual task reviews there. `task` is an alias for this scope.
- Use `task/review/PLAN.review.md` when you want to apply only PLAN feedback.

Before approving, check:

- The service task covers existing orders and optional notes.
- The storefront task depends on the service task.
- Each task names its repository, base branch, and runnable verification checks.
- Model choices and parallelism fit the work you want to run.

Read the revised plan, then approve it:

```text
/pw-review delivery-note signoff task/review/PLAN.review.md approved
```

Every execution invocation checks the current PLAN approval. New feedback can reopen that gate.

## Review an individual task's plan (optional)

To inspect T02 separately before execution, create its review and add your request:

```text
/pw-review delivery-note init task/T02.md
/pw-review delivery-note item task/review/T02.review.md --section Steps --text Keep the note field optional in the form
/pw-review delivery-note T02
```

This changes the selected task plan. PLAN approval still governs execution.

## Execute

```text
/pw-execute delivery-note --wave
```

The first wave runs T01 because T02 depends on it. The recap identifies completed, failed, and newly ready tasks.
Run `/pw-status delivery-note` to find the task links.
Open T01 and read `## Result` for its commit and actual verification output.
For a local diff, ask the agent:

```text
Show T01's diff and verification output in delivery-note. Point out any failed or skipped checks.
```

Check that the service field remains optional and orders without a note pass the compatibility tests.
Run another wave to execute T02 after T01 succeeds:

```text
/pw-execute delivery-note --wave
```

A bare `/pw-execute delivery-note` instead runs the remaining dependency sequence in one invocation.
Completed tasks remain complete. Execution stops at local commits and verification by default.

## Review an execution result (optional)

Read each task's diff and `## Result`.
If T02 uses a required field, create its review if needed, then give a scoped correction:

```text
/pw-review delivery-note init task/T02.md
/pw-review delivery-note item task/review/T02.review.md --section Result --text The note field must remain optional
/pw-review delivery-note T02
```

Task repair normally re-runs verification. If checks remain failed or pending, run:

```text
/pw-execute delivery-note T02
```

Inspect the new result before accepting it. Related dependent tasks can also need fresh checks after an upstream fix.

## Ship

Once verification passes and you want to publish the branches:

```text
/pw-ship delivery-note
```

This pushes eligible branches and opens MRs/PRs. It monitors CI by default.
The recap includes links, branch targets, and check results.
`--skip-build-check` skips CI monitoring; it still publishes changes. It is not a dry run.

To ask teammates for review, build the ready-to-send message (read-only):

```text
/pw-ship delivery-note request-review
```

It lists every open MR with its link, target, current CI status, and assigned reviewers. Add
`--summary`, `--mr-summary`, `--note`, or `--to "Andi, Sari"` for writing help; see
[the recipe](RECIPES.md#ask-teammates-to-review-the-open-mrs).

## Review via MR/PR comments

After a reviewer comments on T01's MR, run:

```text
/pw-ship delivery-note T01 comments
```

The agent reads comments, applies justified fixes, verifies them, pushes updates, and replies on the MR.
The project records the exchange and review-attempt history.
Without a task ID, `comments` handles all eligible open MRs.
If the target branch changes, `/pw-sync delivery-note` refreshes open MR branches and verifies them again.

## Accept results

When the diffs, checks, and review responses satisfy you, tell the agent explicitly:

```text
I reviewed T01 and T02 in delivery-note. Accept both task results and update the project records.
```

This is an acceptance request in chat, not a slash command.
Run `/pw-status delivery-note` to confirm that both tasks are `accepted`.
Approval of the PLAN, task acceptance, and merging an MR are separate decisions.

## Close

```text
/pw-close delivery-note
```

Close checks task acceptance, records learnings, removes eligible worktrees, and marks the project `done`.
It preserves the project directory and branches. Dirty worktrees remain for recovery.
An open MR can remain after close; acceptance does not merge it.

For your next project, keep the [recipes](RECIPES.md) handy and use `/pw-help project <slug>` at each checkpoint.
