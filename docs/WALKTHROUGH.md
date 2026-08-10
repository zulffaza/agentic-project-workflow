# Walkthrough — one made-up project, start to finish

← [back to README](../README.md) · related: [Workflow](./WORKFLOW.md) · [Reference](./REFERENCE.md)

This doc doesn't teach anything new — every rule here is documented properly elsewhere. Its only
job is to make the pipeline **concrete** before you try it: one fictional project, walked through
all nine steps, showing roughly what each artifact actually looks like. No setup required to read
this; nothing here is real output.

> Excerpts below are illustrative and paraphrased, not literal template dumps — the real templates
> (`template/analysis/_TEMPLATE.md`, `template/task/_TEMPLATE-*.md`, `template/_REVIEW.template.md`)
> are the source of truth for exact syntax.

## The scenario

You need to bump Spring Boot 2 → 3 across three services: `payments-api`, `orders-api`, and
`notifications-worker`. It's the same slug used in the README's own Quick Start
(`spring-boot-3-upgrade`) — that's intentional, so the two docs read as one continuous example.

## 1. Drop context

```bash
$PW_HOME/tooling/scaffold.sh spring-boot-3-upgrade
```

You copy the migration ticket and a link to Spring's own 2→3 migration guide into
`context/`, then add one row per input to `context/INDEX.md`:

| File / link | What it is | Source | Trust notes |
|---|---|---|---|
| `JIRA-4821.md` | The migration ticket | Jira `JIRA-4821` | Approved, has target date |
| `spring-migration-guide.md` | Vendor migration notes | spring.io | Official |

...and your best guess at which repos are in scope (the "Repos in scope" table further down in the
same file) — analysis will confirm or correct this, so a rough guess is fine.

## 2–3. Analyze, then review

```
/pw-analyze spring-boot-3-upgrade
```

The agent reads `context/`, digs into the three repos' real state (actual Spring Boot version on
each one's `master`, not a stale branch), and writes `analysis/spring-boot-3-upgrade.md` — a doc
with sections like:

```
## 3. Affected repos & surfaces
| Repo                  | Base branch | Nature of change                          |
|------------------------|-------------|-------------------------------------------|
| payments-api           | master      | Boot 2.7→3.2, javax→jakarta migration     |
| orders-api             | master      | Boot 2.7→3.2, no javax usage found        |
| notifications-worker   | master      | Boot 2.7→3.2 + Kafka client bump (coupled)|

## 5. Risks, unknowns & open questions
- ❓ Q1: notifications-worker's Kafka client bump is coupled to the Boot bump — same task,
  or split? — status: awaiting answer
```

It also auto-creates `analysis/review/spring-boot-3-upgrade.review.md`, empty and `in-review`. You
open it and leave a comment:

```
### R1 · §3 Affected repos — 🔴 open (you, 2026-08-10 09:15)
You're missing that payments-api also has a custom javax.validation setup in
`common-validation/` — check whether that needs its own line item.
```

...and answer its open question inline:

```
### Q1 · §5 Risks — ⏳ awaiting answer (agent, 2026-08-10 09:02)
  ↳ you (2026-08-10 09:20): keep it in the same task — they're coupled, splitting adds risk.
```

Then:

```
/pw-review spring-boot-3-upgrade
```

The agent updates §3, folds your answer into §5, and flips both items to 🟢/✅ with a concrete
`↳ agent:` reply. When you're satisfied, **you** — never the agent — write the Sign-off row:

```
| 2026-08-10 09:45 | you | approved ✅ |
```

That row is the actual gate. Nothing below this point can start until it's there.

## 4–5. Break down, then review

```
/pw-breakdown spring-boot-3-upgrade
```

Refuses if the row above is missing. Once it's there, the agent writes `task/PLAN.md` — a repo
manifest, a dependency DAG, and a task table:

```
| ID  | Title                          | Repo                | depends_on | Execute with |
|-----|---------------------------------|----------------------|-----------|--------------|
| T01 | Bump payments-api to Boot 3     | payments-api         | —         | opus         |
| T02 | Bump orders-api to Boot 3       | orders-api           | —         | sonnet       |
| T03 | Bump notifications-worker+Kafka | notifications-worker | —         | sonnet       |
```

...plus one self-contained `T01.md`/`T02.md`/`T03.md` per row, each with exact steps and a runnable
`## Verify` block (e.g. `mvn -q verify` with an expected "BUILD SUCCESS"). Same review loop as
above, but this time against `task/review/PLAN.review.md` — and **this is the one hard gate** for
execution; per-task review files are optional, created only if you want to send a specific task
back later.

## 6. Execute

```
/pw-execute spring-boot-3-upgrade
```

Refuses unless PLAN is `approved ✅`. The orchestrator spawns one executor per task (T01/T02/T03
have no dependencies on each other here, so they run in parallel), each in its own isolated
`worktree/<repo>/<task-id>-<slug>/` — a real git worktree off the real repo, not a copy. Each
executor makes its edits, commits, runs its `## Verify` block, and pastes the real output into the
task's `## Result`. You'll see a recap like:

```
T01 payments-api           done   commit a1b2c3d   verify: BUILD SUCCESS
T02 orders-api             done   commit 9f8e7d6   verify: BUILD SUCCESS
T03 notifications-worker   done   commit 4c5d6e7   verify: BUILD SUCCESS
```

`/pw-execute` stops here — **committed + verified, nothing pushed.**

## 7. Ship

```
/pw-ship spring-boot-3-upgrade
```

Pushes each task's branch and opens one MR/PR per (repo, base) pair, using your configured Git
forge CLI (`gh`/`glab` — see [`tooling/forges.md`](../tooling/forges.md)):

```
T01  payments-api          MR !142  agent/spring-boot-3-upgrade/T01-boot3-payments → master
T02  orders-api            PR #58   agent/spring-boot-3-upgrade/T02-boot3-orders   → master
T03  notifications-worker  MR !89   agent/spring-boot-3-upgrade/T03-boot3-kafka    → master
```

A reviewer can now comment directly on those MRs/PRs — that's a **separate** loop
(`/pw-ship <slug> [task] comments`), covered in [docs/REVIEW.md](./REVIEW.md); this walkthrough
won't duplicate it.

## 8–9. Accept results, then close

Once each MR is reviewed and you're satisfied, you flip its task to `accepted` (or `verify-failed`
to send one back). When everything's in, close out:

```
/pw-close spring-boot-3-upgrade
```

This captures learnings into the project dashboard's "Decisions & learnings" section (and your
memory tool, if you've configured one — see `tooling/memory.md`), safely tears down the worktrees,
and sets `Status: done`.

---

That's the whole loop, on one made-up example. Ready on a real project? → the Quick Start in
[README.md](../README.md), or [ONBOARDING.md](../ONBOARDING.md) if this machine isn't set up yet.
