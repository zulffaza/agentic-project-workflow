# The workflow, step by step

[README](../README.md) · [Walkthrough](WALKTHROUGH.md) · [Recipes](RECIPES.md) · [Reference](REFERENCE.md)

Move a project through context, analysis, plan, execution, shipping, and close.
The default workflow keeps human approval between analysis and breakdown, and requires current PLAN approval before execution.
You can stop after any command and resume from the files on disk.

| Stage | Run | Inspect before continuing |
|---|---|---|
| Context | `/pw-new <slug>` and `/pw-context <slug> …` | Goals, source inputs, repository scope |
| Analysis | `/pw-analyze <slug>` | Approach options, evidence, risks, questions |
| Plan | `/pw-breakdown <slug>` | `task/PLAN.md`, task steps, dependencies, verification |
| Execute | `/pw-execute <slug>` | Commits, diffs, actual verification output |
| Ship | `/pw-ship <slug>` | MR links, targets, CI, reviewer feedback |
| Close | `/pw-close <slug>` | Accepted task results and reported leftovers |

Use `/pw-review` to record and apply feedback. Use `signoff` to record your approval decision.
For concrete commands at every checkpoint, follow the [walkthrough](WALKTHROUGH.md).

## Step 1 — Context

Create a project with `/pw-new <slug>`. It appears at `$PW_PROJECTS/<slug>/`.
Provide requirements, tickets, document excerpts, relevant code references, or logs in `context/`.
Register each source with `/pw-context <slug> add-input` and each repository with `add-repo`.
Include the real base branch for each repository.

Use `/pw-context <slug> req-init` for an optional requirements brief. Fill it before analysis.
Initialization creates a template copy; source registration records provenance. Neither supplies your requirements.
See [context recipes](RECIPES.md#add-context-or-continue-existing-work) for full argument examples.

Check that `context/INDEX.md` contains useful inputs and repository scope before analysis.
For uncertain evidence, `/pw-research <slug> --context [focus]` checks sources and repository state.

<a id="adopting-existing-in-progress-work"></a>
### Two ways to start: fresh vs. continuation

Use `/pw-new` for fresh work. Use `/pw-adopt` when a branch already contains the work.
Adoption continues the same branch and records its existing state.
Its default intent starts with context, then follows analysis and planning.
Its trailing `review` intent requires an MR and enters review directly.
See [adoption](ADOPTION.md) for multiple branches and mixed projects.

## Step 2–3 — Analysis

Run `/pw-analyze <slug>`. Read the generated `analysis/<topic>.md` and matching review file.
The analysis explains the problem, affected repositories, evidence, approaches, and open questions.
It establishes what changes and why. Task boundaries come during breakdown.

Answer questions with `/pw-review <slug> answer <review-path> <Qid> <answer>`.
Request changes with `item`, then run `/pw-review <slug> analysis` to incorporate them.
Choose the approach and resolve questions before recording approval through `signoff`.

If you use an RFC, publishing its draft is an optional side loop.
An unresolved RFC review item blocks breakdown. Use `/pw-rfc <slug> comments` to fetch feedback, then resolve it through local review.
The [RFC guide](RFC.md) explains draft publication and later PLAN milestones.

## Step 4–5 — Task breakdown

Run `/pw-breakdown <slug>` after analysis approval.
It produces `task/PLAN.md` and one task document per task ID.
PLAN records repositories, dependencies, execution strategy, and model choices.
Each task states its branch, detailed steps, verification commands, and expected results.

Read PLAN and inspect important task files. Request changes through `task/review/PLAN.review.md` or individual task reviews.
Apply feedback with `/pw-review <slug> plan` or selected task IDs.
Once satisfied, approve `task/review/PLAN.review.md` through `signoff`.

Current PLAN approval is the hard gate for execution, including resumed runs.
Individual task review files are optional. Their absence alone does not block execution.
New feedback can reopen an existing approval; inspect the current decision before proceeding.

## Step 6 — Execution

Run `/pw-execute <slug>` to complete the remaining plan in dependency order.
Each task runs in its own Git worktree. Independent tasks can run concurrently within the configured limit.
The agent commits changes, runs each task's verification checks, and records output in its `## Result`.

Choose the scope that fits your next checkpoint:

| Scope | Command | Stops after |
|---|---|---|
| Remaining plan | `/pw-execute <slug>` | Remaining work completes or reports blockers |
| Current ready group | `/pw-execute <slug> --wave` | The tasks ready when this invocation starts |
| Selected tasks | `/pw-execute <slug> T01 T03` | The named scope |

A full resume leaves completed tasks complete and resumes unfinished or failed work.
Explicit task IDs can re-run selected work. Failed prerequisites block their dependents; independent work can continue.
If a session stops, rerun the appropriate scope and inspect the recovered state.

Verification failures from the task's change can trigger bounded self-repair.
Environmental or pre-existing failures remain reported caveats. Read the result and actual output before deciding to accept it.
Execution stops at local commits and verification by default.

For model pins, concurrency, and routing, use [recipes](RECIPES.md#change-models-or-concurrency) and [execution details](EXECUTION.md).
Clean automatic acceptance and `--then-ship` require explicit opt-in; see [clean execution](EXECUTION.md#opt-in-clean-execution-pre-reviewed-plans).

<a id="ship-and-sync"></a>
## Step 7 — Ship (`/pw-ship`), and keeping MRs fresh (`/pw-sync`)

Run `/pw-ship <slug> [task-ids]` when you authorize publication of verified work.
It pushes branches, opens MRs/PRs, and records their links.
MR descriptions explain the changes and verification. Titles include a ticket when the input provenance supplies one.
The command monitors CI by default and reports or repairs failures within its limits.
`--skip-build-check` skips CI monitoring; it still pushes and opens MRs.

When reviewers leave comments, `/pw-ship <slug> [task-ids] comments` reads them, applies justified fixes, verifies, pushes, and replies.
Each attempt keeps a local record and MR description history. See [MR review](REVIEW.md#2-the-mr-review-flow-post-ship).

When an MR's target changes, `/pw-sync <slug> [task-ids]` merges the updated target into the branch, verifies, and pushes.
Merged or closed MRs remain visible as leftovers rather than receiving ordinary comment fixes or sync updates.
MR merging remains your decision.

<a id="stacked-mrs"></a>
### Stacked MRs (when one task needs another's code)

A stack lets a task inherit another task's code in the same repository.
PLAN and task files record `Stacked on: <parent-task>`.
The child starts from the parent's verified commit and targets the parent's branch, so its MR shows the child's changes.
A scheduling dependency or a cross-repository dependency alone does not create a stack.

Preview topology and health with `/pw-ship <slug> stack`.
For existing manually stacked MRs, `stack adopt` previews the import and `stack adopt --apply` records it after confirmation.
If an import changes the approved dependency graph, regenerate and reapprove PLAN before dependent execution or publication.

Ship parents before children. A selected child cannot silently publish an unpublished ancestor.
Merge the parent before the child. After the parent lands, the existing child MR can target the next open ancestor or ultimate base.
Squash or rebase landing can make ancestry unprovable. Promotion then stays blocked for an explicitly approved restack.

Parent fixes must reach affected descendants. Comments mode and sync update them in parent-first order and re-run each descendant's verification.
Changed descendants remain stale until fresh checks pass. Stale tasks cannot ship or close.
Conflicts and failed checks block the affected subtree; unrelated stacks can continue.
Inherited updates receive their own description history. Interrupted remote or local updates remain pending for recovery.
Use [stack troubleshooting](TROUBLESHOOTING.md) and project doctor to identify the pending action.

## Step 8 — Review results

Read each task's diff and `## Result`. `done` records completion; `accepted` records your decision about that result.
If you want a correction, add a task review item and run `/pw-review <slug> T01`.
Task repair normally re-runs verification. Use `/pw-execute <slug> T01` when a selected result needs another run.
Upstream fixes can also require checks on dependent tasks.

When satisfied, explicitly ask the agent to accept the named task results and update project records.
For example: `I reviewed T01 and T02 in delivery-note. Accept both results.`
Use `/pw-status <slug>` to confirm acceptance. There is no separate public acceptance slash command.
In clean execution's optional auto mode, only eligible verified tasks without open review or dependency-impact items become accepted.

## Step 9 — Learn + close (`/pw-close`)

Run `/pw-close <slug>` after all task results are accepted.
It checks the records, captures workflow learnings, cleans eligible worktrees, and marks the project `done`.
If memory is configured, it also records learnings there. Memory is optional.

Close preserves branches and the project directory.
It refuses unsafe cleanup of a dirty worktree or the worktree you occupy, and reports leftovers.
Open or on-hold MRs can remain. Acceptance and project close do not merge them.
Pending stack updates still require recovery before close.

## Maintain an existing project after updating the workflow

New templates improve new projects. Existing project copies keep their recorded content.
Use `/pw-doctor --project <slug> --guidance` to preview recognized guidance updates.
Review the replacements, add `--apply` for that project, then preview again.
This repairs guidance without changing approvals, project phase, MR records, or stack state.
Use project health doctor separately for consistency findings.
See [the update recipe](RECIPES.md#refresh-old-project-guidance-after-a-workflow-update).

## Who owns the dashboard `Status:` field?

Workflow commands maintain the dashboard phase. Review updates feedback and gate decisions without changing that phase.
Use `/pw-status <slug>` to inspect it and `rewind` for an intentional backward move.
Project config values belong to `/pw-config`. Task acceptance remains an explicit decision about task results.

<a id="audit-log--logmd"></a>
## Audit log — `LOG.md`

`LOG.md` records phase changes, agent runs, commits, pushes, MR work, and close actions.
Read it when you need to recover what happened across sessions.
New workflow timestamps use English month names and WIB (UTC+7).
Existing history and source timestamps retain their original values.

## Going back a phase (rewind)

Run `/pw-status <slug> rewind <phase>` when an earlier approach or plan needs revision.
Follow its prompts to record feedback, reopen the review gate, and move the dashboard back.
Re-run the affected phase, apply feedback, and approve the revised artifact.
Downstream files stay on disk; refresh them after upstream reapproval.

Adding feedback to an approved artifact also changes its review decision.
That review transition alone does not rewind the dashboard.
An earlier-phase gate requires explicit confirmation before repair reopens it.
See [review transitions](REVIEW.md#1-local-review-files-pre-ship) for attribution and safeguards.
