---
description: Scaffold a new agentic-workflow project from base/
args: <project-slug>
---
Scaffold a new project for the phased multi-repo workflow. Arguments: {{ARGS}} (first token is
the project slug).

Run:
```bash
{{PW_HOME}}/scaffold.sh {{ARGS}}
```

Then confirm the structure was created and give me a **full onboarding orientation** so I can use
the project without reading the whole base guide. Cover, concisely:

1. **What each dir/file is for** — `context/` (my inputs) + `context/INDEX.md`, `analysis/` +
   `analysis/review/`, `task/PLAN.md` + `task/T0n.md` + `task/review/`, `worktree/`, `sub-agent/`,
   `README.md` (dashboard), `LOG.md` (audit trail).
2. **The gated phase flow** — context → analysis →(gate)→ breakdown →(gate)→ execute → close, and
   that each gate is *my* review approval. Name the command for each phase.
3. **Who fills what** — the legend 🤖 (AI-maintained, don't hand-edit) / 🧑 (you fill) / 🤖🧑
   (both); point out that the dashboard `Status:` is agent-owned and `context/INDEX.md` is yours.
4. **How review + QnA works** — I comment in the phase's `review/` dir (never inline), the agent
   replies `↳ agent:` and flips 🔴→🟢; if the agent has an open question it seeds a `Qn` row I
   answer with `↳ you:`; only I write the Sign-off (date-time to the minute) that clears a gate.
5. **Execution routing** — tasks carry `Execute with: <provider>:<model>`; models map to a
   provider CLI in `base/workflow/providers.md` (Claude models → Claude Code, open-weight → KiloCode,
   extendable); execution pushes + opens MRs (with my OK).
6. **The immediate next 2 actions**, spelled out:
   - add inputs to `projects/<slug>/context/` and fill `context/INDEX.md` (a row per input +
     the first-guess "repos in scope" table),
   - then run **`/pw-analyze <slug>`**.

Keep it a scannable orientation (headers/bullets), not a wall of text. Point to
`../base/README.md` for the full guide and `/pw-status <slug>` to check state any time.
