# Walkthrough — one made-up project, start to finish

← [back to README](../README.md) · related: [Workflow](./WORKFLOW.md) · [Review](./REVIEW.md) ·
[Reference](./REFERENCE.md)

This doc doesn't teach anything new — every rule here is documented properly elsewhere. Its only
job is to make the pipeline **concrete** before you try it: one fictional project, with every point
where you can act on it, showing roughly what each artifact actually looks like. No setup required
to read this; nothing here is real output. Review isn't one step here — it recurs at several
points, each shown as its own section below rather than folded into the phase around it.

> Excerpts below are illustrative and paraphrased, not literal template dumps — the real templates
> (`template/analysis/_TEMPLATE.md`, `template/task/_TEMPLATE-*.md`, `template/_REVIEW.template.md`)
> are the source of truth for exact syntax.

## The scenario

You need to bump Spring Boot 2 → 3 across three services: `payments-api`, `orders-api`, and
`notifications-worker`. It's the same slug used in the README's own Quick Start
(`spring-boot-3-upgrade`) — that's intentional, so the two docs read as one continuous example.

## Drop context

```
/pw-new spring-boot-3-upgrade
```

You copy the migration ticket and a link to Spring's own 2→3 migration guide into `context/`,
then add one row per input to `context/INDEX.md`:

| File / link | What it is | Source | Trust notes |
|---|---|---|---|
| `JIRA-4821.md` | The migration ticket | Jira `JIRA-4821` | Approved, has target date |
| `spring-migration-guide.md` | Vendor migration notes | spring.io | Official |

...and your best guess at which repos are in scope (the "Repos in scope" table further down in the
same file) — analysis will confirm or correct this, so a rough guess is fine.

## Analyze

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

## 4. Approach options

### Option A: big-bang — all three repos in one wave
Bump Boot + javax→jakarta + Kafka client together, one PLAN, parallel tasks.
- **Trade-offs:** fastest to land; biggest blast radius if the Kafka client bump misbehaves.

### Option B: staged — payments-api first, the other two after it's proven in prod
Same end state, split into two PLANs a week apart.
- **Trade-offs:** de-risks the Kafka coupling; two review/ship cycles instead of one.

**Chosen approach:** _pending your review_

## 5. Risks, unknowns & open questions
- ❓ Q1: notifications-worker's Kafka client bump is coupled to the Boot bump — same task,
  or split? — status: awaiting answer
```

## Review the analysis

It also auto-creates `analysis/review/spring-boot-3-upgrade.review.md`, empty and `in-review`, with
a `Q0` already seeded since §4 has two real options:

```
### Q0 · §4 Approach options — ⏳ awaiting answer (agent, 2026-08-10 09:02)
Which approach — A (big-bang) or B (staged)?
```

You open it, answer `Q0`, leave a comment on §3, and answer the other open question:

```
### Q0 · §4 Approach options — ⏳ awaiting answer (agent, 2026-08-10 09:02)
  ↳ you (2026-08-10 09:18): Option A — the Kafka client bump is small enough, staging adds
    ceremony we don't need here.

### R1 · §3 Affected repos — 🔴 open (you, 2026-08-10 09:15)
You're missing that payments-api also has a custom javax.validation setup in
`common-validation/` — check whether that needs its own line item.

### Q1 · §5 Risks — ⏳ awaiting answer (agent, 2026-08-10 09:02)
  ↳ you (2026-08-10 09:20): keep it in the same task — they're coupled, splitting adds risk.
```

Then:

```
/pw-review spring-boot-3-upgrade
```

The agent sets §4's `**Chosen approach:** Option A`, updates §3, folds your Q1 answer into §5, and
flips all three to 🟢/✅ with a concrete `↳ agent:` reply. When you're satisfied, **you** — never
the agent — write the Sign-off row:

```
| 2026-08-10 09:45 | you | approved ✅ |
```

That row is the actual gate — but **`/pw-breakdown` also checks that `Chosen approach:` isn't
still pending**, even if this row already says `approved ✅`. Answering `Q0` isn't optional
paperwork; it's what breakdown actually builds from.

> **AI-assisted option:** turn this on with `/pw-review spring-boot-3-upgrade config analysis
> advisory` (dashboard `AI Review:` line — off by default; `/pw-review spring-boot-3-upgrade
> config` on its own shows all five phases). Once it's `advisory`/`auto`, `/pw-review
> spring-boot-3-upgrade ai` runs a fresh `pw-reviewer` pass first, filing items like `R1` above but
> tagged `(pw-reviewer, …)`. See [docs/REVIEW.md](./REVIEW.md#3-ai-assisted-review-optional-per-phase).

## Break down

```
/pw-breakdown spring-boot-3-upgrade
```

Refuses if the row above is missing. Once it's there, the agent writes `task/PLAN.md` — a repo
manifest, a dependency DAG, and a task table:

```
| ID  | Title                           | Repo                  | depends_on | Execute with |
|-----|----------------------------------|-----------------------|-----------|--------------|
| T01 | Bump payments-api to Boot 3      | payments-api          | —         | opus         |
| T02 | Bump orders-api to Boot 3        | orders-api            | —         | sonnet       |
| T03 | Bump notifications-worker+Kafka  | notifications-worker  | —         | sonnet       |
```

...plus one self-contained `T01.md`/`T02.md`/`T03.md` per row, each with exact steps and a runnable
`## Verify` block (e.g. `mvn -q verify` with an expected "BUILD SUCCESS").

## Review the plan (the hard gate)

Same review loop as analysis, but against `task/review/PLAN.review.md` — and **this is the one
hard gate** for execution:

```
| 2026-08-10 14:10 | you | approved ✅ |
```

> **AI-assisted option:** with `plan` mode set to `auto`, a clean `pw-reviewer` pass can write this
> row itself — tagged `pw-reviewer (auto)`, never blended with your own row. Given this is the only
> hard gate, think carefully before setting this phase to `auto` rather than `advisory`.

## Review an individual task's plan (optional)

Per-task review files are optional and created on demand — and you don't have to wait for a bad
execution result to use one. Say you actually read `T03.md`'s steps before running anything and
notice it pins the wrong Kafka client version:

```
/pw-review spring-boot-3-upgrade T03
```

creates `task/review/T03.review.md` on the spot (if it doesn't exist yet) from your feedback. Add
an item — *"Step 2 pins `kafka-clients:3.4.0`, we need `3.6.1` for the Boot 3.2 baseline"* — and the
agent revises `T03.md`'s steps before `/pw-execute` ever touches that repo. Nothing about T01/T02
is affected; this is scoped to one task, and the PLAN's overall approval above still stands.

> **AI-assisted option:** `task-plan` mode, same idea — `/pw-review spring-boot-3-upgrade ai T03`
> gives T03's plan a fresh look before anything runs, catching exactly this kind of thing without
> you having to read every task file yourself.

## Execute

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

> **Long plan?** The bare `/pw-execute spring-boot-3-upgrade` above resumes **everything**
> outstanding in one invocation — fine for three tasks like this one. For a much longer plan,
> `/pw-execute spring-boot-3-upgrade --wave` instead runs only the tasks that are immediately ready
> right now, then stops and reports which tasks are newly ready for the *next* `--wave` call — a
> checkpoint-sized chunk so a lost session only costs one wave, not the whole remaining DAG.

## Review an execution result (optional)

`done` isn't the same as `accepted` — you still look at what actually got committed. Say T02's
diff looks fine, but T01's changed a config default it shouldn't have. You reject it:

```
Status: verify-failed        # you flip this on T01
```

...then either add an item to `task/review/T01.review.md` or just tell the agent what's wrong.
Running `/pw-review spring-boot-3-upgrade T01` creates that review file from your feedback if it
doesn't exist, applies the fix in the same worktree, and:

```
/pw-execute spring-boot-3-upgrade T01
```

re-runs and re-verifies **just T01**, in its existing worktree — T02 and T03 are untouched, and
you don't re-run the whole plan.

> **AI-assisted option:** `task-exec` mode — a fresh `pw-reviewer` pass looks at what actually got
> committed (not just the plan) and can flag T01's config-default change itself, before you do.

## Ship

```
/pw-ship spring-boot-3-upgrade
```

Pushes each task's branch and opens one MR/PR per (repo, base) pair, using your configured Git
forge CLI (`gh`/`glab` — see [`tooling/docs/forges.md`](../tooling/docs/forges.md)):

```
T01  payments-api          MR !142  agent/spring-boot-3-upgrade/T01-boot3-payments → master
T02  orders-api            PR #58   agent/spring-boot-3-upgrade/T02-boot3-orders   → master
T03  notifications-worker  MR !89   agent/spring-boot-3-upgrade/T03-boot3-kafka    → master
```

## Review via MR/PR comments

A reviewer can now comment directly on the pushed diff, in your Git host's own UI — a genuinely
different review entry point from everything above (those were all local `.review.md` files; this
one lives on the MR itself). Say someone comments on MR !142:

*"This bumps `common-validation` too — was that intentional, or should it be a separate MR?"*

```
/pw-ship spring-boot-3-upgrade T01 comments
```

runs the full loop: **FETCH** the open thread → **FIX** in T01's worktree if a change is warranted
(here, maybe just clarifying, no code change needed) → **REPLY** on the thread with a concrete
answer (never a bare "done") → **MIRROR** the exchange into `task/T01.md`'s `## Result` and
`task/review/T01.review.md` as a 🟢 resolved item, so the project dir stays the record even for an
MR-driven change. Run `/pw-ship spring-boot-3-upgrade comments` (no task ID) to sweep **every**
open MR in the project in one pass instead of one at a time. Full mechanics, including why a
general/no-diff comment still counts: [docs/REVIEW.md](./REVIEW.md#2-the-mr-review-flow-post-ship).

> **AI-assisted option:** `ship` mode extends the same delegation to this surface too — see
> [docs/REVIEW.md](./REVIEW.md#3-ai-assisted-review-optional-per-phase) for how it applies here.

## Accept results

Once each MR is reviewed and you're satisfied, you flip its task to `accepted` (the one status
only you ever set).

## Close

```
/pw-close spring-boot-3-upgrade
```

Captures learnings into the project dashboard's "Decisions & learnings" section (and your memory
tool, if you've configured one — see [docs/MEMORY.md](./MEMORY.md)), safely tears down the
worktrees, and sets `Status: done`. **`accepted` ≠ merged** — open/on-hold MRs don't block close-out.

---

That's the whole loop, on one made-up example, with every review entry point shown separately.
Ready on a real project? → the Quick Start in [README.md](../README.md), or
[ONBOARDING.md](../ONBOARDING.md) if this machine isn't set up yet.
