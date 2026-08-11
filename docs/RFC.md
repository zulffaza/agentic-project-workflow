# RFC publishing (optional side-loop)

← [back to README](../README.md) · related: [Review & feedback](./REVIEW.md) ·
[Workflow](./WORKFLOW.md)

`/pw-rfc` is an **optional, manually-triggered** side-loop — same shape as `/pw-ship`/`/pw-sync`,
just publishing to an RFC doc instead of a git forge. It never introduces a new phase and never
touches the dashboard `Status:`. Skip this guide entirely if you don't write RFCs for a project;
nothing else in the pipeline notices either way.

## What's an RFC, and why would you use this

**RFC** = "Request For Comments" — an old, widely-borrowed term (originally IETF) for a written
proposal that lays out the background, the approach, and the risks of a piece of work *before* (or
while) you build it, specifically so people **outside your immediate review loop** — another team,
a lead, a stakeholder who won't read a git diff — have a natural place to weigh in. If your org
already has a "write an RFC before doing the big thing" culture (in Lark, Confluence, Google Docs,
wherever), this side-loop is a bridge into that, rather than a replacement for it.

**The actual goal here** is narrow and deliberate: the pipeline's own local `.review.md` files (see
[`docs/REVIEW.md`](./REVIEW.md)) already give *you* a tight review loop on the analysis and the
plan — that's the mandatory gate. `/pw-rfc` is what you reach for **on top of that**, only when a
piece of work is big or cross-team enough that people who aren't doing the day-to-day review still
need visibility and a chance to comment — externalizing content you've *already* approved locally,
never the other way around. If nobody outside your own review needs to see this, skip it entirely;
nothing else notices.

## Generate vs. Publish

`/pw-rfc` always writes/updates `<project>/rfc/RFC.md` locally — the **Generate** step, and it
needs **no external tool at all**. **Publish** — pushing those sections to a real doc platform
(Lark today; Confluence/Google Docs/Notion documented but not yet implemented, see
[`tooling/docs/rfc-backends.md`](../tooling/docs/rfc-backends.md)) — is a separate, optional step layered on
top, controlled by `PW_RFC_BACKEND` in `pw.config.sh`. Leave it unset (or `"markdown"`) and you get
a maintained local RFC doc with zero external dependency — that's the bundle-wide default, so a
fresh clone (including an AI agent onboarding itself) can run `/pw-rfc` immediately.

## The two waves

Each wave is gated by an **existing** approval gate — RFC publishing only ever externalizes an
artifact you've already approved through the normal pipeline:

| Wave | Command | Gate | Fills |
|---|---|---|---|
| 1 | `/pw-rfc <slug> [--target <ref>]` | analysis `approved ✅` | Background · Requirements + Out of Scope · Solution (+ diagrams) · Dependencies · (Rollout/Rollback Plan, only if you ask) |
| 2 | `/pw-rfc <slug> milestone` | `task/PLAN.md` `approved ✅` | Milestone (from the PLAN's DAG groups + task table + SP/timeline) · Conclusion |

Glossary and the References subsections (Open questions?, RFC review meeting notes) stay
human-owned placeholders — the agent never fills those. Before touching anything external, `/pw-rfc`
always shows you the local `rfc/RFC.md` diff and confirms — same discipline as `/pw-ship` confirming
its push list.

## Backend config + target resolution

```sh
PW_RFC_BACKEND="markdown"   # "markdown" (default) | "lark" | (stub only) confluence/google-docs/notion
PW_RFC_LARK_TEMPLATE=""     # only used when backend=lark
PW_RFC_LARK_SPACE=""        # optional global default target; usually left blank
PW_RFC_NOTES=""
```

Which external doc a publish goes to is resolved in order: this run's `/pw-rfc --target <ref>` flag
→ the project's own `rfc/META.md` (persisted from an earlier `--target`) → the backend's configured
default, if any. Once a project has a target, later runs reuse it without repeating the flag — so
you can set it per-project (via `--target` once) instead of a single global default.

## Walkthrough — one example, start to finish

Continuing [docs/WALKTHROUGH.md](./WALKTHROUGH.md)'s own `spring-boot-3-upgrade` example: say this
one's big enough that another team's lead wants visibility before you break it into tasks.

1. **Analysis gets approved** (the normal `analysis/review/spring-boot-3-upgrade.review.md`
   sign-off — RFC publishing never happens before this).
2. **Wave 1 publish:**
   ```
   /pw-rfc spring-boot-3-upgrade --target <lark-doc-or-folder-ref>
   ```
   Generates/updates `rfc/RFC.md` locally, shows you the diff, and — since `--target` was given —
   pushes Background/Requirements/Solution/Dependencies into the configured backend (or stays
   purely local under the `markdown` default). You share the doc link with the other lead.
3. **They leave a comment** on the RFC doc's "Solution" section: *"Have you considered the
   Kafka client version skew with `notifications-worker`'s other consumers?"*
4. **Pull it in:**
   ```
   /pw-rfc spring-boot-3-upgrade comments
   ```
   Fetches that thread (read-only) and adds one 🔴 open item to its own dedicated review file,
   `analysis/review/RFC.review.md` (separate from `spring-boot-3-upgrade.review.md` — created on
   demand if it doesn't exist yet), quoting the comment with a link back to the thread.
5. **You decide it's worth addressing** — either answer it inline in the review file yourself, or
   just tell the agent; run `/pw-review spring-boot-3-upgrade` to fold the answer into the analysis
   (its `↳ agent:` reply is the durable record of what changed). **You** reply to and resolve the
   actual thread on the platform — the agent never touches it.
6. **Push the revision:** re-run `/pw-rfc spring-boot-3-upgrade` — it updates only the affected
   section(s) in the external doc, never a whole-doc overwrite, so nothing else on that page (their
   comment thread included) gets disturbed.
7. **Later, once the PLAN is approved:**
   ```
   /pw-rfc spring-boot-3-upgrade milestone
   ```
   fills in Milestone + Conclusion from the approved `task/PLAN.md`.

That's the whole loop: local review stays the mandatory gate throughout; the RFC doc is a
read-mostly window onto already-approved work, and the only thing that ever flows back in is a
comment quote — never a direct edit.

## The comment loop — read-only outward, always

Unlike the MR-comment flow (see [Review & feedback → the MR review flow](./REVIEW.md#2-the-mr-review-flow-post-ship)),
`/pw-rfc <slug> comments` **never writes back** to the external platform. It only pulls:

```
you/a teammate comments on the RFC doc (thread on some section)
        │
        ▼
/pw-rfc <slug> comments
        │
        ├─ 1. FETCH open threads   (the backend's list_comments — read-only)
        └─ 2. MIRROR into the project dir
                 • analysis/review/RFC.review.md  (one 🔴 open item per thread: quote, author,
                   link, which section)
                 • rfc/META.md's "Comment tracking" table  (one row per thread — reply count seen +
                   solved — via `pw-lib.sh rfc comment-seen`, so a re-run tells a brand-new thread
                   from one that just got a new reply from one that's already fully mirrored)
```

You then run the **existing** `/pw-review` to apply fixes to the analysis locally — its `↳ agent:`
reply on each item is the durable record of what changed (no new review machinery). **You reply to
and resolve the actual thread on the platform yourself**, using that local record as your
reference. Re-run `/pw-rfc <slug>` (or `milestone`) afterward to push the revised sections. Under
the `markdown` backend, `comments` is a clear no-op — there's nothing external to read.

## Diagrams

Block/Sequence Diagram subsections generate via an isolated, ad-hoc sub-agent call (not a
persistent agent — this role never recurs across tasks or crosses a provider boundary, see
`tooling/agents/README.md`'s bar for when a new agent def is warranted). On any rendering failure,
the section gets a plain-text placeholder instead and the rest of the RFC still publishes — a
diagram is never a single point of failure for the whole push.

## Adding a backend

`/pw-rfc` never hardcodes a platform — every backend implements the same 4-operation contract
(`create_from_template` / `fetch_anchors` / `update_section` / `list_comments`) documented in
[`tooling/docs/rfc-backends.md`](../tooling/docs/rfc-backends.md). The one non-negotiable rule for any
backend: `update_section` must be scoped to that section's own anchor, **never** a whole-doc
overwrite — that's what keeps a reviewer's comment from being silently orphaned.
