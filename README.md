# 🛠️ Agentic Multi-Repo Project Workflow

Take a piece of work across many repos from a pile of context to reviewed, shipped MRs — driven by
AI agents, **gated by you at every phase**. It's a set of `/pw-*` slash commands plus a handful of
templates, portable across agent CLIs (Claude Code, KiloCode, …).

```
 context  →  analyze  →  break down  →  execute  →  ship  →  close
   📥          🔍            🧩           ⚙️        🚀       ✅
  drop      what & why    PLAN + tasks  worktrees   MRs    learn +
  inputs    (you sign off) (you sign off) commit+verify    tear down
```

Every project lives in its own directory under `IdeaProjects/projects/<slug>/` — a copy of this
bundle's [`template/`](./template). One phase writes, you review, the next phase starts. Nothing goes
outward (no push, no MR) until you explicitly run `/pw-ship`.

---

## Quick start

```bash
# 0. one-time: onboard this machine (installs the skill + /pw-* commands + sub-agents for your CLIs)
./bootstrap.sh && source ./pw-env.sh

# 1. scaffold a project
$PW_HOME/tooling/scaffold.sh spring-boot-3-upgrade

# 2. drop context into projects/spring-boot-3-upgrade/context/, then in your agent CLI:
/pw-analyze   spring-boot-3-upgrade     # → analysis/  (review it, then sign off)
/pw-breakdown spring-boot-3-upgrade     # → task/PLAN.md + T0n.md  (review it, then sign off)
/pw-execute   spring-boot-3-upgrade     # → runs tasks in worktrees; stops at committed + verified
/pw-ship      spring-boot-3-upgrade     # → pushes branches + opens MRs (the explicit publish step)
/pw-close     spring-boot-3-upgrade     # → tears down worktrees, captures learnings, Status → done
```

**Two ways to start.** Fresh (`/pw-new`, above) — or **continuation** if you're already
mid-development: `/pw-adopt <slug> <repo> <branch> [mr-url]` snapshots the in-progress work and
continues it *on the same branch* (with or without an existing MR). Run it **once per in-progress
branch** to adopt multi-repo work already in flight. Everything from analysis on is identical. Full
guide → **[docs/ADOPTION.md](./docs/ADOPTION.md)**.

New here or on a fresh machine? **[ONBOARDING.md](./ONBOARDING.md)** has the full setup, including
adding your own agent CLI as a provider.

> **Path variables used throughout the docs** (so nothing is tied to one machine/username):
> `$PW_HOME` = this bundle's dir · `$PW_PROJECTS` = its parent (where `<slug>` projects go) ·
> `$PW_REPOS` = the repos root (where your sibling git repos live). `./bootstrap.sh` exports these
> and stamps the real paths into the generated commands.

## The nine steps at a glance

| # | Step | Produces | Gate | Command |
|---|------|----------|------|---------|
| 1 | Drop context | files in `context/` + `INDEX.md` row | — | `/pw-new` |
| 2–3 | Analyze + review | `analysis/<topic>.md` | ✅ analysis approved | `/pw-analyze` · `/pw-review` |
| 4–5 | Break down + review | `task/PLAN.md` + `T0n.md` | ✅ **plan approved (only hard gate)** | `/pw-breakdown` · `/pw-review` |
| 6 | Execute | commits in `worktree/*` (committed + verified) | per-task DoD | `/pw-execute` |
| 7 | Ship | pushed branches + MRs | you confirm the push | `/pw-ship` |
| 8 | Review results | accepted tasks | ✅ you accept each task | `/pw-review` |
| 9 | Learn + close | learnings, teardown, Status→done | — | `/pw-close` |

Keeping open MRs fresh as their base moves is a side-loop: **`/pw-sync`**. Another optional
side-loop, **`/pw-rfc`**, publishes approved analysis/plan content to an RFC doc (any configured
platform, or a local-only doc by default) — see **[docs/RFC.md](./docs/RFC.md)**. Full detail →
**[docs/WORKFLOW.md](./docs/WORKFLOW.md)**.

## Dig deeper

| Guide | What's in it |
|-------|--------------|
| 📋 **[docs/WORKFLOW.md](./docs/WORKFLOW.md)** | Every step in detail · who owns `Status:` · the `LOG.md` audit trail · rewinding a phase |
| 🔀 **[docs/ADOPTION.md](./docs/ADOPTION.md)** | The continuation workflow — adopt in-progress branches, the two intents, mixed projects |
| 💬 **[docs/REVIEW.md](./docs/REVIEW.md)** | The two review entry points — local `.review.md` files **and** MR comments — and how they reconcile |
| 📝 **[docs/RFC.md](./docs/RFC.md)** | Optional side-loop — publish approved analysis/plan content to an RFC doc, any platform or none |
| ⚙️ **[docs/EXECUTION.md](./docs/EXECUTION.md)** | Orchestrator vs executor · picking a model/agent per task · cross-provider execution · worktrees |
| 📖 **[docs/REFERENCE.md](./docs/REFERENCE.md)** | Bundle layout · project anatomy · naming conventions · the full `/pw-*` command table + generator |
| 🚀 **[ONBOARDING.md](./ONBOARDING.md)** | Fresh-machine / teammate setup · registering a new provider · optional memory |

## Why it's shaped this way

- **Gated phases.** Each phase stops for a human sign-off, so mistakes get caught at the cheapest
  point. The **PLAN sign-off is the only hard gate**; per-task reviews are optional.
- **State on disk, not in a chat.** Every phase writes files, so a run is resumable and auditable
  (`LOG.md`), and you review one artifact type at a time.
- **Isolated worktrees.** Each task runs in its own `git worktree` off the real repo, so parallel
  tasks never collide and nothing touches your working checkout.
- **Portable & shareable.** One source of truth for commands/agents/skill, stamped per provider by
  `bootstrap.sh`. Paths stay machine-independent via `{{PW_*}}` tokens. Clone it, run bootstrap,
  go — see [ONBOARDING.md](./ONBOARDING.md).

Invoke the `project-workflow` skill any time an agent needs these conventions restated.
