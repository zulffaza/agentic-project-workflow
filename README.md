# 🛠️ Agentic Multi-Repo Project Workflow

Take a piece of work across many repos from a pile of context to reviewed, shipped MRs — driven by
AI agents, **gated by you at every phase**. It's a set of `/pw-*` slash commands plus a handful of
templates, portable across agent CLIs (Claude Code, KiloCode, …).

**The idea, plainly:** say you need to change something across several repos — an upgrade, a new
field threaded through three services, whatever. Instead of doing the thinking yourself, you hand
an agent the raw material and let it work in stages: first it explains *what* needs to change and
*why* (you read that and correct it before anything else happens), then it turns your approved
understanding into a concrete task list (you approve that too — the one hard gate), then it
actually makes the changes, each in its own disposable copy of the repo so nothing collides — and
nothing is pushed anywhere until you say so. You're never surprised by a change you didn't see
coming, and you never wrote the boilerplate.

**Terms used below:** a **worktree** is an isolated, disposable checkout of a repo (so parallel
tasks never collide with each other or your own checkout) · **DAG** = the task dependency graph
(which tasks must finish before others can start) · **MR** ("merge request", GitLab) = the same
thing as a GitHub **PR** · an **agent** is the AI process you're driving; a **sub-agent** is one it
spawns to do a single task in isolation (full definitions: [docs/EXECUTION.md](./docs/EXECUTION.md)).

```
 context  →  analyze  →  break down  →  execute  →  ship  →  close
   📥          🔍            🧩           ⚙️        🚀       ✅
  drop      what & why    PLAN + tasks  worktrees   MRs    learn +
  inputs    (you sign off) (you sign off) commit+verify    tear down
```

Every project lives in its own directory under `$PW_PROJECTS/<slug>/` (wherever you cloned this
bundle — see [ONBOARDING.md](./ONBOARDING.md), not a fixed folder name) — a copy of this bundle's
[`template/`](./template). One phase writes, you review, the next phase starts. Nothing goes
outward (no push, no MR) until you explicitly run `/pw-ship`.

**New here?** Read in this order: this Quick Start (2 min) → optionally
[docs/WALKTHROUGH.md](./docs/WALKTHROUGH.md) to see one made-up project go through every phase with
example output (5 min) → [ONBOARDING.md](./ONBOARDING.md) when you're ready to actually install it
(10 min).

---

## Quick start

```bash
# 0. one-time: onboard this machine (installs the skill + /pw-* commands + sub-agents for your CLIs)
./bootstrap.sh && source ./pw-env.sh

# 1. scaffold a project (in your agent CLI)
/pw-new spring-boot-3-upgrade

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
adding your own agent CLI as a provider. Leaving/uninstalling? `./offboard.sh` is the exact inverse
of `./bootstrap.sh` — see ONBOARDING.md's [Offboarding](./ONBOARDING.md#offboarding--uninstalling) section.

> **Path variables used throughout the docs** (so nothing is tied to one machine/username):
> `$PW_HOME` = this bundle's dir · `$PW_PROJECTS` = its parent (where `<slug>` projects go) ·
> `$PW_REPOS` = the repos root (where your sibling git repos live). `./bootstrap.sh` exports these
> and stamps the real paths into the generated commands.

## The 6 core stages at a glance

| Stage | Produces | Command |
|---|---|---|
| Context | files in `context/` + `INDEX.md` row | `/pw-new` (or `/pw-adopt`) |
| Analyze → review → approve | `analysis/<topic>.md` | `/pw-analyze` · `/pw-review` |
| Break down → review → approve **(the only hard gate)** | `task/PLAN.md` + `T0n.md` | `/pw-breakdown` · `/pw-review` |
| Execute → (optional) review a result | commits in `worktree/*` (committed + verified) | `/pw-execute` |
| Ship → review via MR/PR comments | pushed branches + MRs | `/pw-ship` |
| Learn + close | learnings, teardown, Status→done | `/pw-close` |

**Review recurs at several of these, not just once** — after analysis, after breakdown (the plan
as a whole, and optionally any individual task's steps), after execution (per task, if you reject a
result), and after ship (comments on the MR/PR itself). See
**[docs/WALKTHROUGH.md](./docs/WALKTHROUGH.md)** for all of them walked through on one example, or
**[docs/REVIEW.md](./docs/REVIEW.md)** for the mechanics of each. Every one of them is human-only by
default, but can optionally be delegated to a fresh AI review pass instead (per project, per phase)
— see that same doc's "AI-assisted review" section.

Keeping open MRs fresh as their base moves is a side-loop: **`/pw-sync`**. Another optional
side-loop, **`/pw-rfc`**, publishes approved analysis/plan content to an RFC doc (any configured
platform, or a local-only doc by default) — see **[docs/RFC.md](./docs/RFC.md)**. Full detail →
**[docs/WORKFLOW.md](./docs/WORKFLOW.md)**.

## Dig deeper

| Guide | What's in it |
|-------|--------------|
| 🧭 **[docs/WALKTHROUGH.md](./docs/WALKTHROUGH.md)** | One made-up project through every stage *and* every review point, with example output — read this first if you're new |
| 📋 **[docs/WORKFLOW.md](./docs/WORKFLOW.md)** | Every step in detail · who owns `Status:` · the `LOG.md` audit trail · rewinding a phase |
| 🔀 **[docs/ADOPTION.md](./docs/ADOPTION.md)** | The continuation workflow — adopt in-progress branches, the two intents, mixed projects |
| 💬 **[docs/REVIEW.md](./docs/REVIEW.md)** | The two review entry points — local `.review.md` files **and** MR comments — how they reconcile, and the optional AI-assisted delegated review pass |
| 📝 **[docs/RFC.md](./docs/RFC.md)** | Optional side-loop — publish approved analysis/plan content to an RFC doc, any platform or none |
| 🧠 **[docs/MEMORY.md](./docs/MEMORY.md)** | Optional cross-project recall — what it's for, why bother, how to turn it on |
| ⚙️ **[docs/EXECUTION.md](./docs/EXECUTION.md)** | Orchestrator vs executor · picking a model/agent per task · cross-provider execution · worktrees |
| 📖 **[docs/REFERENCE.md](./docs/REFERENCE.md)** | Bundle layout · project anatomy · naming conventions · the full `/pw-*` command table + generator |
| 🚀 **[ONBOARDING.md](./ONBOARDING.md)** | Fresh-machine / teammate setup · registering a new provider · optional memory · offboarding/uninstalling |

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
