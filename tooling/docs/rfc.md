# RFC-publishing policy (optional, pluggable)

The pipeline **does not depend on any specific RFC doc platform.** Publishing is a bonus side-loop,
never a gate — if you don't configure a backend, `/pw-rfc` still works, generating a local doc, and
nothing in the pipeline blocks.

## The always-available record
`/pw-rfc` always writes/updates `<project>/rfc/RFC.md` on disk, **with no external tool required**
— this is the **Generate** step, and it happens regardless of `PW_RFC_BACKEND`. **Publish** — pushing
those sections out to an external doc platform (Lark, Confluence, …) — is a separate, additional,
optional step layered on top. If you never configure a real backend, that's the whole story: you
get a maintained local RFC doc and skip every external call, same spirit as `memory.md`'s "no tool
→ agents only use README/LOG" default.

## Is RFC even the right side-loop for this project?
`/pw-rfc` only ever externalizes work **already approved** through the pipeline's own gates — it
never introduces a new phase and never touches the dashboard `Status:` (context→analysis→
breakdown→executing→review→done). It only appends to `LOG.md`, exactly like `/pw-ship`/`/pw-sync`.
Use it when a project is big/cross-team enough to need a written RFC and discussion before
breakdown; skip it entirely for smaller projects — nothing else in the pipeline notices either way.

## Canonical section schema
Every RFC (any backend) uses this schema — see
[`template/rfc/_TEMPLATE-RFC.md`](../../template/rfc/_TEMPLATE-RFC.md) for the literal skeleton. A
backend's `fetch_anchors` (in [`rfc-backends.md`](./rfc-backends.md)) maps these canonical names
onto that platform's *real* template headings, so a differently-worded template still works — the
mapping is data, not a hardcoded assumption that every platform's template reads identically.

| Section | Filled by | Wave |
|---|---|---|
| Glossary | 🧑 you (never the agent) | — |
| Background | 🤖 agent, from analysis §1–2 | 1 |
| Requirements + Out of scope | 🤖 agent, from analysis §1 + §6 | 1 |
| Solution (Approach #1/#2 + diagrams) | 🤖 agent, from analysis §4 | 1 |
| Dependencies | 🤖 agent, from analysis §3 | 1 |
| Rollout Plan / Rollback Plan | 🧑🤖 both, **only if you ask** | 1 (on request) |
| Milestone | 🤖 agent, from `task/PLAN.md`'s DAG + task table + SP/timeline | 2 |
| Conclusion | 🤖 agent | 2 |
| References → Open questions? | 🧑 you (RFC-comment pulls land in `analysis/review/RFC.review.md` instead — see below) | — |
| References → RFC review meeting notes | 🧑 you (never the agent) | — |

## The two publish waves — each gated by an EXISTING approval gate
- **Wave 1** (`/pw-rfc <slug> [--target <ref>]`) — refuses unless analysis is `approved ✅`
  (`pw-lib.sh phase <slug>` / the analysis review file's Sign-off row). Fills Background through
  Dependencies (+ Rollout/Rollback if asked).
- **Wave 2** (`/pw-rfc <slug> milestone`) — refuses unless `task/PLAN.md` is `approved ✅`. Fills
  Milestone + Conclusion from the approved PLAN.
- Neither wave sets the dashboard `Status:` or otherwise advances the pipeline — RFC publishing is
  purely a side-effect of an already-approved artifact, recorded via `pw-lib.sh rfc state/dashboard`
  + `pw-lib.sh log` (same audit-trail convention as every other mutator).
- Before touching any external backend, `/pw-rfc` **always shows the local diff of `rfc/RFC.md`
  and confirms with you first** — same discipline as `/pw-ship` confirming the push list.
- `rfc init` (creating `rfc/RFC.md` + stamping `rfc/META.md`) runs **inside each wave, only after
  its gate passes** — never in a shared preamble ahead of the gate check. A refused run leaves
  nothing on disk; this is what makes "RFC publishing only ever externalizes already-approved
  work" actually true, not just a stated intent.
- **If a backend other than `markdown` has no resolvable target** (no `--target`, no persisted
  `rfc/META.md` target, no configured default) on a project's first publish, `/pw-rfc` **stops and
  asks you** where to create the doc — it never guesses a location (e.g. a Drive root folder). This
  was found missing by a live fresh-context test: an agent with no target correctly available will
  otherwise improvise a plausible-looking but unreviewed destination. **This check happens at the
  actual publish sub-step, inside the wave, only after that wave's gate has already passed** — not
  in the shared preamble. A second fresh-context test caught the ordering flaw in an earlier draft:
  checking it before the gate meant an agent could ask "where should I publish?" for a project that
  isn't even approved yet. Cheap, local checks (the gate, generation, the local diff) always come
  first; the target question only fires once there's real, approved content ready to publish.
- **If the external template pre-populates a section with no corresponding generated content**
  (e.g. its own "Approach #2" placeholder when analysis found no alternative), `/pw-rfc` leaves
  that section's existing content untouched — it never deletes or edits it without being asked.

## The section-scoped-update mandate (non-negotiable)
A backend's `update_section` (per `rfc-backends.md`) must touch **only the block/anchor range for
that one section** — never a whole-doc overwrite. This is the single load-bearing guarantee of the
whole feature: a reviewer's comment is anchored to a block/range elsewhere in the doc, and a
whole-doc rewrite orphans it. If a backend genuinely cannot do scoped updates (note this explicitly
in its `rfc-backends.md` row), `/pw-rfc` must warn loudly before publishing rather than overwrite
silently.

## Comment loop — read-only outward, always
`/pw-rfc <slug> comments` only **pulls**. It calls the backend's `list_comments` for every thread,
using **the platform's own resolved-state** (e.g. Lark's `is_solved`) as the primary signal for
what still needs attention — the same way the MR-comment flow implicitly relies on GitLab/GitHub's
own thread-resolved flag rather than inventing a parallel one. A resolved thread is only worth
noting once (an informational append to its existing item, never a new one); an unresolved thread
either becomes a new item or, if already tracked, has just its *new* replies appended.

**Per-thread tracking, not a single "latest" pointer.** State lives in `rfc/META.md`'s "Comment
tracking" table (thread ID → reply count seen → solved), upserted via `pw-lib.sh rfc comment-seen`
(same marker-keyed upsert shape as `context/INDEX.md`'s adoption rows — never duplicated, always
updated in place). An earlier design used a single scalar "last thread ID seen," which broke a
concrete case caught by a live walkthrough: comment A arrives, comment B arrives later (cursor
now points at B), then A gets a *new reply* — under a scalar cursor, A is either silently dropped
forever (if the cursor is read as a watermark) or re-imported as a phantom duplicate (if read as
an exact match). Per-thread tracking has no such ambiguity: A's own row just gets its reply count
bumped, and the new reply gets appended to A's existing item — never a duplicate, never dropped.

The agent **never replies to or resolves anything on the external platform, and never rewrites an
item's existing text** — new replies are *appended* underneath, same convention as local
`.review.md` files never being rewritten. You reply/resolve on the platform yourself, and decide
whether the analysis needs a change via the existing `/pw-review` (its `↳ agent:` reply is the
durable record of what changed — no new review machinery). Re-run `/pw-rfc <slug>` afterward to
push the revision. This mirrors `docs/REVIEW.md`'s MR-comment flow's FETCH → MIRROR steps, but
deliberately **drops** its FIX-in-worktree/REPLY-on-thread steps — those are code-review mechanics
that don't apply to RFC prose, and you explicitly own the on-platform reply here. No-ops with a
clear message under the `markdown` backend (nothing external to pull).

## Diagrams — auto-generated by default, isolated, and failure never blocks the rest of the publish
Block Diagram / Sequence Diagram subsections **auto-generate by default** for each Approach
actually written up (skip only if explicitly told not to) via an **ad-hoc, isolated sub-agent
call** (not a persistent agent definition — see `tooling/agents/README.md`'s bar for when one is
warranted; this role never recurs across tasks, never crosses a provider boundary, and only exists
to contain a mermaid-rendering failure): generate mermaid from the relevant analysis section, hand
it to the sub-agent to render (a Lark whiteboard, for the `lark` backend, per `lark-whiteboard`),
and **on any failure, substitute a plain-text placeholder noting the diagram needs manual
follow-up** — the rest of that section, and every other section, still publishes. The generation
attempt is the default, unconditional behavior; only the failure-handling path is conditional. A
diagram must never be a single point of failure for the whole RFC push.

## `rfc/` project-subdir contents
- **`rfc/RFC.md`** — the generated canonical doc (see schema above). Created idempotently by
  `pw-lib.sh rfc init <slug> <backend>` (mirrors `review-init`'s create-if-missing/else-no-op).
- **`rfc/META.md`** — 🤖-owned via `pw-lib.sh rfc init|target|state|comment-seen` (never hand-edit):
  backend, target ref, last revision pushed, wave1/wave2-published flags, and a **"Comment
  tracking" table** — one row per thread (ID → reply count seen → solved), not a single scalar,
  so per-thread state (new vs. updated vs. already-resolved) is actually representable. `rfc init`
  stamps `Backend:` with the **actual** resolved backend it's called with — never a hardcoded
  guess — so this file is correct from the moment it exists.
- Comments never get their own `rfc/review/` — they land in the existing
  `analysis/review/RFC.review.md`, reusing `/pw-review`'s machinery rather than inventing a
  parallel one.

## Config (`pw.config.sh`)
```sh
PW_RFC_BACKEND="markdown"   # "markdown" (default) | "lark" | (stub only) confluence/google-docs/notion
PW_RFC_LARK_TEMPLATE=""     # only used when backend=lark
PW_RFC_LARK_SPACE=""        # optional global default target — usually left blank; see resolution order
PW_RFC_NOTES=""             # freeform notes, same spirit as PW_MEMORY_NOTES
```
**Target resolution order** (which external doc a publish goes to): `/pw-rfc --target <ref>` flag →
`rfc/META.md`'s persisted `Target:` (set by an earlier `--target` or `pw-lib.sh rfc target`) →
`PW_RFC_<BACKEND>_SPACE`-style config default. Once a project has a target, subsequent runs reuse
it without repeating the flag. **If none of these resolve and the backend needs one, the agent
stops and asks — it never falls back to an unreviewed default location.**

**Rule for agents:** treat RFC publishing as best-effort, opt-in enrichment on top of an
already-complete pipeline artifact. Never block, refuse, or fail a phase because a backend is
unset, unreachable, or a publish fails — report it and continue; the local `rfc/RFC.md` is never at
risk even if the external push fails.
