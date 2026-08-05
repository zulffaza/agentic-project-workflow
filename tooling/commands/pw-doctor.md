---
description: Check that your installed /pw-* commands + skill are in sync with the bundle (--fix to repair)
args: [--fix]
---
Arguments: {{ARGS}}.

Run the project-workflow sync check and show its output:
```bash
{{PW_HOME}}/tooling/pw-doctor.sh {{ARGS}}
```
It verifies, per enabled provider (from `pw.config.sh`), that the installed `project-workflow`
skill and the generated `/pw-*` command files match what this bundle would produce now — catching a
moved/renamed bundle, edited command sources, or a stale skill.

- If everything is in sync, say so and stop.
- If anything is out of sync and `--fix` was **not** passed, summarize exactly what drifted (which
  provider, skill vs commands) and tell me to re-run `/pw-doctor --fix` (or `{{PW_HOME}}/bootstrap.sh`).
- If `--fix` was passed, report what it repaired and confirm the re-check is clean.

Never hand-edit the generated command files — regeneration via the script is the fix.
