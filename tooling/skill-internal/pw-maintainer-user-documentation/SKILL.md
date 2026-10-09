---
name: pw-maintainer-user-documentation
description: Write, review, or refresh agentic-project-workflow user guides and user-facing guidance after a bundle change. Use with pw-maintainer for onboarding, walkthroughs, command recipes, reference pages, and troubleshooting. This is an internal writing skill, not a command for running projects.
---

# User documentation for the workflow

Help a reader choose the next action, run it correctly, inspect the result, and understand any gate.
Apply this skill to the requested pages or guidance. A documentation refresh does not authorize installation, project mutations, publication, or unrelated runtime changes.

This skill is read as a file under `skill-internal/`. It is not provider-installed.
For repository doctrine and the change protocol, use [pw-maintainer](../pw-maintainer/SKILL.md).
For the user/maintainer boundary and issue routing, read its [boundary reference](../pw-maintainer/references/boundary-and-docs.md).

## Ground the instructions in the current bundle

Read the affected guide and its canonical command definition under `tooling/commands/`.
If the definition leaves behavior unclear, inspect the owning implementation or existing fixture tests.
Use current sources to settle argument syntax, defaults, scope, and side effects; do not copy a remembered command into the guide.

For an update against main, compare the relevant changes before editing. Preserve the existing review worktree and unrelated edits.
Separate upstream changes from the documentation changes. Resolve overlapping prose by keeping both the updated behavior and the reader improvements.

Check these details whenever an example depends on them:

- Required operators, positional arguments, flag values, and multi-word parsing.
- Project-relative versus context-relative versus filesystem paths.
- Scope selectors versus filenames, task IDs, or approval decisions.
- Recording feedback versus applying it, PLAN approval versus task acceptance, and acceptance versus MR merging.
- Preview versus apply, local verification versus remote publication, and the exact effect of skip flags.

Treat template hints and hidden comments as user-facing when agents can relay them. Edit them only when they are in the requested scope.
Keep internal helpers and implementation links in maintainer material, following the canonical boundary rules.

## Give each page a clear job

| Page | Reader's job |
|---|---|
| README | Understand the benefit and choose installation, first use, or continuation |
| Onboarding | Select an enabled provider, install it, verify availability, and recover setup |
| Walkthrough | Complete one coherent example with checkpoints and expected artifacts |
| Recipes | Jump to a recurring task and copy a command with its prerequisites |
| Reference | Look up syntax, parameter meanings, values, and file locations |
| Specialist guide | Understand behavior or tradeoffs after the basic path works |
| Troubleshooting | Match a symptom to a supported recovery action and inspect the outcome |

Improve an existing page before adding a new one. Link shared explanations instead of repeating them across every guide.
Use a compact jump menu when a long page contains several distinct reader tasks.
Keep the main path usable without reading advanced model, provider, stack, or automation details.

## Write an executable example

Use a fictional, consistent project with plausible repository names and task IDs.
State which values to replace. Verify naming restrictions and prerequisites against the current sources.
Keep shell setup separate from commands entered in an agent session; label chat requests as chat requests.
Do not imply that a hypothetical output was observed in a live project.

For each important action, include enough to answer:

1. When do I use it, and what must exist first?
2. Where do I enter it, and what do its parameters mean?
3. What changes or gets created, and where do I inspect it?
4. What do I review or approve before continuing?

Explain unfamiliar syntax at its first useful example. Prefer the discoverable flag form when it clarifies separate free-text fields.
For example, `item <review-path> --section <heading> --text <request>` needs an explanation of the reviewed heading, requested change, and recording/applying distinction.
For a scope word such as `plan`, verify what files it selects and show an exact review-path alternative when the example targets one file.

Do not tell readers to inspect a diff or verification result without explaining how to find it.
Use the supported status/help surface for discovery, or a concrete chat request for local evidence.
When an optional detour creates an artifact, ensure the later main path still works if that detour is skipped.
For resume and repair recipes, distinguish outstanding tasks from completed tasks. Avoid prescribing a second execution run after a verified repair; check the execution and review definitions.

## Design for scanning and reading

Use tables for command catalogs, parameter meanings, repeated fields, and comparisons. Keep cells short; move qualifications below the table.
Use numbered lists for ordered steps or precedence, with each item rendered separately.
Use bullets for parallel checks or choices. Use short prose to explain how an action works and why the reader needs it.

Break dense sections by reader question or action, rather than turning one paragraph into a long bullet.
Put explanation outside copyable command blocks. Keep each example command complete; do not invent shell continuations for agent-session commands.
Use plain headings and defined terms. Preserve existing anchors or add aliases when changing linked headings.

## Verify and report the result

Read the changed path as a newcomer: setup, inputs, review, execution, publication, acceptance, and recovery where relevant.
Check linked pages for conflicting instructions and examples after a source update.

- Check local links and heading anchors, including renamed headings and new navigation.
- Check examples against command definitions, including parameter parsing and action scope.
- Run `git diff --check` and the repository's required checks for the change type; see [testing.md](../../docs/testing.md).
- For substantial layout changes, render the affected Markdown at desktop and narrow widths. Inspect tables, lists, and command-block scrolling.
- Report what was checked, what remains unverified, and whether edits are local, committed, or published.

Distinguish a documentation check, an offline fixture test, and a live project run.
If an uninstalled worktree fails installation/config checks, report those failures rather than changing active provider installs or weakening tests to clear them.
Do not claim that generic Markdown previews prove appearance on every host.
