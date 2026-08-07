# RFC publishing (optional side-loop)

← [back to README](../README.md) · related: [Review & feedback](./REVIEW.md) ·
[Workflow](./WORKFLOW.md)

`/pw-rfc` is an **optional, manually-triggered** side-loop — same shape as `/pw-ship`/`/pw-sync`,
just publishing to an RFC doc instead of a git forge. It never introduces a new phase and never
touches the dashboard `Status:`. Skip this guide entirely if you don't write RFCs for a project;
nothing else in the pipeline notices either way.

## Generate vs. Publish

`/pw-rfc` always writes/updates `<project>/rfc/RFC.md` locally — the **Generate** step, and it
needs **no external tool at all**. **Publish** — pushing those sections to a real doc platform
(Lark today; Confluence/Google Docs/Notion documented but not yet implemented, see
[`tooling/rfc-backends.md`](../tooling/rfc-backends.md)) — is a separate, optional step layered on
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

## The comment loop — read-only outward, always

Unlike the MR-comment flow (see [Review & feedback → the MR review flow](./REVIEW.md#the-mr-review-flow-post-ship)),
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
                 • rfc/META.md's Comment cursor    (so a re-run doesn't re-import the same threads)
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
[`tooling/rfc-backends.md`](../tooling/rfc-backends.md). The one non-negotiable rule for any
backend: `update_section` must be scoped to that section's own anchor, **never** a whole-doc
overwrite — that's what keeps a reviewer's comment from being silently orphaned.
