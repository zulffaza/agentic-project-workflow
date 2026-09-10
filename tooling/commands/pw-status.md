---
description: Show a project's phase, task status + open review items — or, with "rewind", move the dashboard Status back to an earlier phase
args: <project-slug> [rewind <phase>]
---
Arguments: {{ARGS}} (project slug). Project dir:
`{{PW_PROJECTS}}/<slug>`.

**If the 2nd argument is literally `rewind`, this is the rewind flow, not a status report — skip
everything below and follow this instead** (3rd argument is the phase to rewind to: `context` |
`analysis` | `breakdown` | `executing` | `review`):

1. Confirm the human actually wants this — going back a phase is a deliberate, visible move, not
   something to do on a hunch. Say what will change (current phase → target phase) and wait for a
   clear go-ahead before touching anything.
2. Check the target phase's review file has a fresh `[OPEN]` item describing what needs to change,
   and a new `in-review` Sign-off row (never delete the old `approved` row — it's history). If
   neither exists yet, tell me to add them first rather than rewinding into a phase with no record
   of *why*.
3. Run `…/{{PW_HOME}}/tooling/pw-lib.sh status <slug> <phase> --rewind` — this is the only place
   that flag is ever passed; a plain `status` call always refuses to move backward, by design.
4. Report the new phase and point me at the phase command to re-run (`/pw-analyze` / `/pw-breakdown`
   / …), then `/pw-review` to re-approve.

---

<!-- Pre-flight: deterministic status report (no agent needed) -->
```bash
{{PW_HOME}}/tooling/pw-status.sh <slug>
```

The script produces the full status report (phase, task table, review items, AI Review modes,
LOG.md lines, blockers, next action, CLI auth status) — show it to the user as-is; `## Blockers`
is heuristic, so trust `pw-preflight.sh` over it for gate decisions. Exit 2 + `pw-status: …` =
bad slug / no such project. No agent invocation needed for report mode — only reason on top of
the report if the user asks a follow-up the fixed sections don't answer.
