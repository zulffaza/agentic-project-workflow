---
name: pw-new
description: Scaffold a new agentic-workflow project from the bundle template
args: "--project <project-slug>"
scope: project
---

**Load shared guidance first.** Read the `pw-orchestration` skill's common rules
(`references/common.md`) before acting: authorization, operation scope, helper ownership, and
reporting. Load only the phase-specific references this operation needs. A read-only operation
must not run execution or mutation procedures.
Scaffold a new project for the phased multi-repo workflow. Arguments: {{ARGS}} — the project is
named `--project <project-slug>`; nothing is positional.

- **`/pw-new --project <project-slug>`** — scaffold that project, then give me the onboarding
  orientation below.

Run:
```bash
{{PW_HOME}}/tooling/scripts/toolchain/scaffold.sh --project <slug>
```

Then confirm the structure was created and give me a **full onboarding orientation** so I can use
the project without reading the whole base guide. Cover, concisely:

1. **What each dir/file is for** — `context/` (my inputs) + `context/INDEX.md` + the optional
   `context/_REQUIREMENTS.template.md` brief, `analysis/` + `analysis/review/`, `task/PLAN.md` +
   `task/T0n.md` + `task/review/`, `worktree/`, `README.md` (dashboard), `LOG.md` (audit trail).
   (Reusable sub-agents aren't per-project — they're seeded globally from `tooling/agents/`.)
2. **The gated phase flow** — context → analysis →(gate)→ breakdown →(gate)→ execute → ship →
   close, and that each gate is *my* review approval. Name the command for each phase.
3. **Who fills what** — the legend 🤖 (AI-maintained, don't hand-edit) / 🧑 (you fill) / 🤖🧑
   (both); point out that the dashboard `Status:` is agent-owned and `context/INDEX.md` is yours.
4. **How review + QnA works** — I comment in the phase's `review/` dir (never inline), the agent
   replies `↳ agent:` and flips `[OPEN]`→`[RESOLVED]`; if the agent has an open question it seeds a `Qn` row I
   answer with `↳ you:`; only I write the Sign-off (date-time to the minute) that clears a gate.
5. **Execution routing** — tasks carry one `## Execution routes` row per current provider, with
   an execution provider, a mandatory model, and separate subagent/tuning columns. **Always write
   the explicit provider and a concrete model** (e.g. `claude:opus`, `kilo:command_code/...`,
   `cursor:cursor-grok-4.5-high`, `codex:gpt-6.1-sol`); there is no static model→provider lookup.
   The dashboard `Execute with:` summary is derived, and a task with no route for the current
   provider cannot dispatch. As a rough mental model: Claude models tend to
   run via Claude Code, open-weight/third-party ones via KiloCode; the exact mechanics are in
   `{{PW_HOME}}/tooling/docs/providers.md`. `/pw-execute` stops at committed + verified, and
   `/pw-ship` is the separate step that pushes + opens MRs (with my OK).
6. **The immediate next 2 actions**, spelled out:
   - add inputs to `projects/<slug>/context/` and fill `context/INDEX.md` (a row per input +
     the first-guess "repos in scope" table),
   - then run **`/pw-analyze --project <slug>`**.

Keep it a scannable orientation (headers/bullets), not a wall of text. Point to
`{{PW_HOME}}/README.md` for the full guide and `/pw-status --project <slug>` to check state any time.
