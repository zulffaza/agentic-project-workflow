# Find commands and understand the bundle

[README](../README.md) · [Recipes](RECIPES.md) · [Reference](REFERENCE.md)

Use the workflow through its installed commands and skills. For daily use, start with command discovery below.
This page also gives contributors the bundle location, so existing links to this guide remain useful.

## Find a command or feature

| You need… | Run in your agent session |
|---|---|
| A list of available commands | `/pw-help` |
| Arguments and examples for review | `/pw-help command pw-review` |
| Next steps for your project | `/pw-help project <slug>` |
| The phase sequence and gates | `/pw-help workflow` |
| Documentation for a concept | `/pw-help find <term>` |

Help reads current command sources. Use it when an example does not match your installed version.
For copyable examples with expected outcomes, read [recipes](RECIPES.md).
Operations use `/pw-*` commands. If older project guidance names internal scripts, preview its supported updates with guidance doctor.

## Choose the right check or repair

| Scope | Inspect | Repair |
|---|---|---|
| Installed commands, skills, and agent definitions | `/pw-doctor` | `/pw-doctor --fix` |
| Project documents, config, and state consistency | `/pw-doctor --project <slug>` | `/pw-doctor --project <slug> --fix` |
| Recognized outdated project guidance | `/pw-doctor --project <slug> --guidance` | `/pw-doctor --project <slug> --guidance --apply` |

Guidance preview writes nothing. Review it before applying changes to the selected project, then preview again.
Health repair and guidance repair are separate modes. Customized guidance stays untouched outside recognized matches.
See [the guidance recipe](RECIPES.md#refresh-old-project-guidance-after-a-workflow-update) for skipped text and expected results.

## Change settings

Use `/pw-config <slug> show` for project settings and `/pw-config global show` for machine settings.
Change project values through `/pw-config <slug> set <key> <value>`.
The [reference](REFERENCE.md#what-you-can-update-per-project-pw-config) lists supported keys and values.
For setup, provider configuration, and uninstall instructions, read [onboarding](../ONBOARDING.md).

## Where contributors start

The bundle's `tooling/` tree contains command sources, agent definitions, skills, maintainer references, and regression checks.
Contributor instructions start at `tooling/AGENTS.md`. That file directs contributors to the relevant internal references.

Installed provider files are generated from the bundle's single source of truth.
Repair their drift through `/pw-doctor --fix`. A change made only in a generated copy disappears during regeneration.
The workflow checks the boundary between command-based user guidance and implementation references.
