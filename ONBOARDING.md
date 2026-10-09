# Onboarding

Install the workflow for the agent CLI you use, then verify that its commands are available.
These steps also work when recovering a machine.

| You want to… | Go to |
|---|---|
| Install for the first time | [Prerequisites](#prerequisites) and [setup](#setup-in-4-steps) |
| Repair missing or outdated commands | [Installation recovery](#troubleshooting--pw-doctor) |
| Update an existing project's instructions | [Guidance update](#existing-projects-after-an-update) |
| Look up everyday commands | [Day-to-day](#day-to-day) |
| Add a custom CLI or uninstall | [Provider setup](#register-a-new-provider) · [Uninstall](#offboarding--uninstalling) |

## Prerequisites

- `git`, `bash`, and `perl` available in your terminal.
- At least one supported agent CLI installed and authenticated.
- `gh` for GitHub or `glab` for GitLab, authenticated for repositories you plan to publish or adopt.

An agent provider is the CLI that runs your workflow. Choose its config name from this table:

| Agent CLI | Executable on `PATH` | Config name |
|---|---|---|
| Claude Code | `claude` | `claude` |
| KiloCode | `kilo` | `kilo` |
| OpenCode | `opencode` | `opencode` |
| Cursor CLI | `agent` | `cursor` |
| Codex CLI | `codex` | `codex` |

These providers are built in. You must still enable the ones you use in `PW_PROVIDERS` during setup.
For a different CLI, see [custom provider registration](#register-a-new-provider).

<a id="onboard-in-3-steps"></a>
## Setup in 4 steps

### 1. Clone the bundle

Replace both placeholders with your repository URL and repository root:

```bash
git clone <repository-url> <your-repos-root>/projects/agentic-project-workflow
cd <your-repos-root>/projects/agentic-project-workflow
```

The default layout places the bundle under `projects/`, alongside the project records it creates:

```text
<your-repos-root>/
├── storefront/                     repository you change
├── order-service/                  repository you change
└── projects/
    ├── agentic-project-workflow/    workflow bundle
    └── delivery-note/               project record created later
```

Other layouts work. Set the repository root explicitly in step 3 if it differs from this example.

### 2. Select your agent providers

Create your local config only if it does not exist:

```bash
test -f pw.config.sh || cp pw.config.example.sh pw.config.sh
```

Open `pw.config.sh`. Replace its `PW_PROVIDERS` line with the CLIs you actually use.
The example defaults to `PW_PROVIDERS=(claude)`.

| Your setup | Line in `pw.config.sh` |
|---|---|
| Codex only | `PW_PROVIDERS=(codex)` |
| Claude only | `PW_PROVIDERS=(claude)` |
| KiloCode only | `PW_PROVIDERS=(kilo)` |
| Cursor only | `PW_PROVIDERS=(cursor)` |
| OpenCode only | `PW_PROVIDERS=(opencode)` |
| Multiple CLIs | `PW_PROVIDERS=(claude codex)` |

Save the file before continuing. This config is local and Git-ignored.
Other defaults are enough for a first project; custom provider hooks are unnecessary for these five CLIs.

### 3. Install and load the paths

Run from the bundle directory:

```bash
./bootstrap.sh
source ./pw-env.sh
```

Bootstrap installs for providers that are both enabled and available on `PATH`.
Read its detected-provider list. If your provider is missing, check the executable and the config line from step 2.

If your repositories live outside the default layout, use this installation command instead:

```bash
PW_REPOS=/path/to/your/repos ./bootstrap.sh
source ./pw-env.sh
```

Loading `pw-env.sh` exposes the paths used in these guides. You can add its `source` line to your shell profile.

### 4. Verify in your agent session

```text
/pw-doctor
/pw-help
```

Setup is ready when doctor reports your installed provider in sync and help lists the workflow commands.
For a missing command, follow [installation recovery](#troubleshooting--pw-doctor).

In Codex, select the installed `pw-*` skill corresponding to the command. The guides use `/pw-*` as shared workflow names.
The bundle installs Codex commands as explicit-invocation skills under `~/.codex/skills/`; it seeds no Codex sub-agents.

Next, complete the [first-project walkthrough](docs/WALKTHROUGH.md).
Use `/pw-help project <slug>` whenever you need the next command for an existing project.

## What bootstrap did

| Installed or created | Purpose |
|---|---|
| `pw.config.sh`, if absent | Your local provider and machine settings |
| Workflow skills | Phase, review, and RFC instructions, where supported |
| `/pw-*` commands or command skills | The workflow interface for each enabled, detected provider |
| Seeded agents, where supported | Orchestrator, executor, reviewer, researcher, analyst, and task writer roles |
| `pw-env.sh` | Paths for the bundle, projects, and repositories |

The paths are:

- `$PW_HOME`: the workflow bundle.
- `$PW_PROJECTS`: where project records live; the bundle's parent by default.
- `$PW_REPOS`: where your Git repositories live; two levels above the bundle by default.

Re-run `./bootstrap.sh` after changing providers or updating the bundle.
Use `--check` to inspect provider detection without writing files. Use `--force` to replace existing workflow skill installs.

## Troubleshooting — `pw-doctor`

If workflow commands are unavailable, run the terminal setup again:

1. Confirm the correct `PW_PROVIDERS` line in `pw.config.sh`.
2. Run `./bootstrap.sh` from the bundle directory and inspect the detected providers.
3. Check command availability in your agent session again.

If commands are available but stale, use doctor in your agent session:

| Command | Result |
|---|---|
| `/pw-doctor` | Report installation drift |
| `/pw-doctor --fix` | Repair supported installation drift |

Doctor checks the enabled CLI, installed skills, generated commands, and seeded agents where supported.
`✓` means in sync; `✗` names a missing, stale, or mismatched surface.

Use doctor after updating the bundle or changing providers. It checks installation sync; project health uses `/pw-doctor --project <slug>`.
Setup and uninstall use terminal scripts because they create or remove the workflow command surface.

### Existing projects after an update

Run `/pw-doctor` to inspect installation sync, then `/pw-doctor --fix` if repair is needed.
This updates the installed workflow. Instructions already copied into existing projects can still use older wording.

Preview guidance updates for one project:

```text
/pw-doctor --project <slug> --guidance
```

Inspect the replacements. To apply them to that project, add `--apply`, then preview again.
The [guidance recipe](docs/RECIPES.md#refresh-old-project-guidance-after-a-workflow-update) explains the scope, skipped text, and recheck.
The preview includes recognized legacy review hints in analysis and task review files.
It updates their instructions without applying feedback or changing approval decisions.
Project health repair (`--fix`) is a separate mode.

## Day-to-day

Use these commands in your agent session. `<slug>` is your project name.
Follow the [walkthrough](docs/WALKTHROUGH.md) for the complete sequence.

| Command | When to use it |
|---|---|
| `/pw-new <slug>` | Scaffold a project |
| `/pw-context <slug> <operator> …` | [Add requirements, inputs, and repositories](docs/RECIPES.md#add-context-or-continue-existing-work) |
| `/pw-analyze <slug>` | Turn context into an analysis |
| `/pw-review <slug>` | Apply recorded feedback for the current phase |
| `/pw-breakdown <slug>` | Turn approved analysis into PLAN and tasks |
| `/pw-execute <slug>` | Resume outstanding work, commit, and verify |
| `/pw-ship <slug>` | Push verified branches and open MRs |
| `/pw-sync <slug>` | Refresh open MR branches against updated targets |
| `/pw-close <slug>` | Check acceptance, clean eligible worktrees, and record learning |

Commands to keep nearby:

| Command | Purpose |
|---|---|
| `/pw-status <slug>` | Show progress, blockers, and next steps |
| `/pw-help project <slug>` | Show commands suited to the project's current state |
| `/pw-help command pw-review <slug>` | Explain review syntax with project-specific paths |
| `/pw-doctor [--fix]` | Check installation sync; add `--fix` to repair it |
| `/pw-rfc <slug>` | Publish an optional RFC document |

### Record feedback and approval

`/pw-review` has separate actions for recording feedback, applying it, and approving the result.
Use `--section` and `--text` with `item` to make the location and request clear:

```text
/pw-review <slug> item task/review/PLAN.review.md --section Verification --text Add tests for existing orders
```

- `task/review/PLAN.review.md` is the project-relative review file that receives your feedback.
- `--section` names the heading or anchor in the **reviewed artifact**, such as `Verification` or `Execution strategy`.
- `--text` contains the change you want the agent to make. Both values can contain spaces.

The command records an item. Run `/pw-review <slug> task/review/PLAN.review.md` to apply it to PLAN only.
Read the revision before recording approval.

| Review action | Command |
|---|---|
| Create a review for an existing artifact | `/pw-review <slug> init <artifact-path>` |
| Create missing reviews for the current phase | `/pw-review <slug> init-all` |
| Answer an existing question | `/pw-review <slug> answer <review-path> Q2 <answer>` |
| Record your approval | `/pw-review <slug> signoff <review-path> approved` |

Your first new item after approval queues a fresh review cycle automatically.
See [review parameters and scopes](docs/REVIEW.md#add-feedback-with-section-and-text) for multi-word examples and scope selection.

### Checkpoints in the loop

- Review the analysis before breakdown. **PLAN approval is the hard execution gate**; per-task reviews are optional.
- Execution stops at local commits and verification. `/pw-ship` publishes them.
- A bare `/pw-execute <slug>` resumes outstanding work. Add `--wave` to stop after the current ready group.
- Read task diffs and results before asking the agent to accept them. Acceptance is separate from PLAN approval.

See [execution options](docs/EXECUTION.md) for routing, waves, and optional automatic acceptance.

## Memory (optional — not required)

The pipeline records decisions in each project's README and LOG. It works without a memory tool.

- Keep `PW_MEMORY=none` (the default) to skip memory steps.
- To use EverOS, mem0, or another tool, set `PW_MEMORY` and `PW_MEMORY_NOTES` in `pw.config.sh`.
- When configured, agents search memory during analysis and capture learning at close-out.

See [memory setup and benefits](docs/MEMORY.md).

## Register a new provider

### Enable a built-in CLI

For Claude, KiloCode, OpenCode, Cursor, or Codex, edit `PW_PROVIDERS` in `pw.config.sh` and re-run `./bootstrap.sh`.
Use the [provider selection table](#2-select-your-agent-providers). No custom hooks are required.

### Register a different CLI

Custom provider support is configured in `pw.config.sh`.
Ask your agent to inspect the bundle's provider hook contract and built-in implementations before defining new hooks.

1. Add the CLI's config name to `PW_PROVIDERS`.
2. Define detection, install-directory, and command-rendering hooks in the local config.
3. Add agent hooks if the CLI supports seeded agents. Add a headless hook if it must receive cross-provider tasks.
4. Re-run `./bootstrap.sh`, then inspect `/pw-doctor`.

Without the optional cross-provider hook, the CLI can still work with its own provider.
Each provider's installation must work independently of the other providers' directories.
Compatibility scanning by a vendor CLI does not replace the bundle's installation.

### Choose a model backend

An API provider is the model backend used by an agent CLI. This is separate from `PW_PROVIDERS`.

- KiloCode defaults to its built-in `kilo` gateway. Additional backends require their own configured credentials.
- Set `PW_KILO_API_PROVIDERS` or `PW_OPENCODE_API_PROVIDERS` to restrict eligible model-ID prefixes for that CLI.
- Claude uses its model aliases. Cursor and Codex use their own gateways and have no API-provider axis in this bundle.

Prefix entries can contain slashes. A Kilo backend registered under the gateway uses a path such as `kilo/alibaba-token-plan`.
Read [catalog lookup and connection names](docs/EXECUTION.md#check-the-model-catalog-before-pinning) before changing backend scope or model pins.
Query the catalog with `kilo models`; prefix filters are not catalog command arguments.

## Offboarding / uninstalling

Run uninstall from the bundle directory in a terminal. Preview first:

```bash
./offboard.sh
```

The preview reports proposed removals. To apply them:

```bash
./offboard.sh --yes
```

| Optional flag | Scope |
|---|---|
| `--provider kilo` | One provider; use comma-separated names for several |
| `--all-known` | All built-in providers, including ones removed from `PW_PROVIDERS` |

Uninstall removes matching workflow skills, generated commands, and seeded agents where supported.
It skips edited or foreign files whose contents do not match the bundle's generated output.

It preserves:

- Your `pw.config.sh`.
- Project records under `$PW_PROJECTS`.
- The workflow bundle itself.

Keep the preview report if you need to review skipped files or proposed removals later.

## A note about where things live

This repo is the reusable **bundle** only. The `<slug>` projects you scaffold live in
`$PW_PROJECTS` (the bundle's parent) and are yours — they are never committed here. The bundle
directory itself holds the docs you're reading plus the machinery the `/pw-*` commands call;
for command discovery, read [Find workflow commands](docs/TOOLING.md).
