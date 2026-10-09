# Agentic Project Workflow

Turn a change across repositories into a reviewed plan, verified commits, and merge requests.
You provide the goal and review the decisions. AI agents analyze the code and execute each task in an isolated checkout.

Use this workflow for coordinated upgrades, features across services, or unfinished work on existing branches.
Each project keeps its inputs, plans, review history, and results on disk, so you can resume in another session.

A worktree is an isolated Git checkout. An MR is a GitLab merge request, equivalent to a GitHub pull request (PR).

```text
Context → Analysis → Plan → Execute → Ship → Close
          approve    approve  verify    MRs   accept + learn
```

## Quick start

1. [Install the workflow](ONBOARDING.md). It supports Claude Code, KiloCode, OpenCode, Cursor CLI, and Codex CLI.
2. Follow the [first-project walkthrough](docs/WALKTHROUGH.md). It includes context, feedback, approval, and acceptance commands or requests.
3. Use [command recipes](docs/RECIPES.md) when you return to an existing project.

During [setup](ONBOARDING.md#setup-in-4-steps), select your provider in `pw.config.sh` before installing.
The example config enables Claude only.

Once installed, run workflow commands in your agent session. In Codex, select the installed `pw-*` skill for the corresponding command.
Examples use the shared `/pw-*` names throughout these guides.

```text
/pw-new delivery-note
/pw-help project delivery-note
```

The first command creates a project. The second shows its phase, review state, and suggested commands.
A project slug uses lowercase letters, digits, and hyphens, starting with a letter or digit. Use `delivery-note`, not a title with spaces.
Next, [add your inputs and repositories](docs/WALKTHROUGH.md#drop-context), then request analysis.

### Already mid-development? Adopt it instead of starting fresh

If work exists on a branch, continue that branch through the workflow:

```text
/pw-adopt delivery-note storefront feature/delivery-note
```

An optional MR URL connects existing review work. The trailing `review` intent handles an existing MR directly.
See [adoption](docs/ADOPTION.md) for both paths and multiple branches.

## The 6 core stages at a glance

| Stage | You do | The agent produces |
|---|---|---|
| Context | Provide requirements, sources, and repositories | Registered inputs in `context/INDEX.md` |
| Analysis | Answer questions and approve the approach | `analysis/<topic>.md` |
| Plan | Review task boundaries, dependencies, and checks, then approve | `task/PLAN.md` and `task/T01.md`, etc. |
| Execute | Run all tasks, selected tasks, or one ready wave | Commits and verification results in isolated worktrees |
| Ship | Authorize publication with `/pw-ship` | Pushed branches and MRs/PRs |
| Close | Accept task results, then run `/pw-close` | Recorded learnings and safe worktree cleanup |

PLAN approval is the hard gate before execution, including resumed runs.
Analysis approval precedes breakdown. Individual task reviews are optional.
With default settings, execution stops at committed and verified work. Publishing requires `/pw-ship`.
Optional controls have separate purposes:

- [AI review](docs/RECIPES.md#use-ai-review-with-human-approval) can add an independent review pass.
- [Automatic acceptance and chained shipping](docs/EXECUTION.md#opt-in-clean-execution-pre-reviewed-plans) can shorten a pre-reviewed execution run.

## Find the command you need

| Your question | Run in your agent session |
|---|---|
| What commands exist? | `/pw-help` |
| What do I run next? | `/pw-help project delivery-note` |
| What happened in this project? | `/pw-status delivery-note` |
| How do I use one command? | `/pw-help command pw-review delivery-note` |
| Where is a feature documented? | `/pw-help find acceptance` |

Replace `delivery-note` with your project name. These help and status commands only read state.

## Dig deeper

| You want to… | Read |
|---|---|
| Install, update, or uninstall | [Onboarding](ONBOARDING.md) |
| Complete your first project | [Walkthrough](docs/WALKTHROUGH.md) |
| Copy a command for a specific task | [Recipes](docs/RECIPES.md) |
| Understand each stage and its gate | [Workflow](docs/WORKFLOW.md) |
| Find syntax, config values, or project files | [Reference](docs/REFERENCE.md) |
| Continue existing branches or MRs | [Adoption](docs/ADOPTION.md) |
| Give feedback or enable AI review | [Review](docs/REVIEW.md) |
| Control execution and model routing | [Execution](docs/EXECUTION.md) |
| Recover from a problem | [Troubleshooting](docs/TROUBLESHOOTING.md) |
| Refresh an older project's instructions | [Guidance update recipe](docs/RECIPES.md#refresh-old-project-guidance-after-a-workflow-update) |
| Publish an optional RFC or use memory | [RFC](docs/RFC.md) · [Memory](docs/MEMORY.md) |

## What to check before approving

| Checkpoint | Inspect |
|---|---|
| Analysis approval | Scope, approach, compatibility risks, and answers to open questions |
| PLAN approval | Repository/base branch, dependencies, task boundaries, and runnable verification checks |
| Task acceptance | Actual diff, verification output, unresolved feedback, and publication/review status |

Use `/pw-status <slug>` to find task and MR links. Ask the agent to show a task's local diff if it is not published yet.

## Why it's shaped this way

Review the approach before the agent edits repository code. Review the task plan before it executes.
Each task records the checks it ran and the output, so you can assess the result.
Worktrees let independent tasks run together while preserving your checkout.
Existing branches can join through adoption, and open MRs can receive fixes through the same project record.
