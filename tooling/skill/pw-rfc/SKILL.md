---
name: pw-rfc
description: Author or update the RFC doc for a project-workflow project — the section-by-section mapping from analysis/task content to the canonical RFC schema, written for a broader reader than the analysis doc, including the multi-solution-area case. Use when running /pw-rfc's Wave 1/Wave 2 fill step, or whenever handed an approved analysis doc (+ optionally task/PLAN.md) and told to write or refresh an RFC. Does NOT own publish mechanics (backend selection, target resolution, section-scoped external writes, doc hygiene) — see tooling/docs/rfc.md and tooling/docs/rfc-backends.md for those; this skill is the authoring guide layered on top.
---

# pw-rfc (RFC authoring guide)

The **how to write each section**, given an approved `analysis/<topic>.md` (and, at Wave 2,
`task/PLAN.md`). The publish mechanics — which backend, how a section maps onto that backend's real
headings, the hygiene rules for a filled section — already live in `tooling/docs/rfc.md` and
`tooling/docs/rfc-backends.md`; read those too before writing anything, this skill doesn't repeat
them. What this skill adds: exactly which analysis/task content feeds each canonical section, and
the one rule that applies to all of them — **write for a broader reader than the analysis doc's
own audience.** The analysis doc assumes whoever reads it already has the context; an RFC doesn't —
reword accordingly, don't just copy sentences across.

## Section-by-section

1. **Glossary** — 🧑 human-owned, the agent never fills this. If you're asked to suggest entries
   anyway, list abbreviations/unfamiliar terms a reader outside this project's immediate context
   would need explained.
2. **Background** — from analysis §1 (Problem/goal), reworded for breadth: assume the reader
   doesn't know this codebase.
3. **Requirements** — from `context/REQUIREMENTS.md` if present, else analysis §1. **Split into
   `### Functional Requirements` / `### Non-Functional Requirements` subsections whenever both
   kinds are actually present** (performance/security/observability asks are non-functional; "the
   flag must be off by default" is functional) — don't force the split if there's genuinely only
   one kind. Reword for breadth, same as Background.
4. **Out of Scope** — from `context/REQUIREMENTS.md`'s own Out of scope section if present, else
   analysis §6. Reworded for breadth.
5. **Solution** — from analysis §4, as detailed as the analysis supports (analysis already uses the
   fixed Design/Per-repo-impact/Trade-offs skeleton — carry that structure through, don't flatten
   it). **Multiple solution areas:** if the project has more than one `analysis/<topic>.md` (see the
   analysis template's "MULTIPLE LARGE SOLUTION AREAS" note), write one `## Solution for <area>`
   RFC section per analysis doc, each internally structured the same way (chosen approach +
   diagrams, briefly the rejected alternatives) — never assume there's exactly one "Solution"
   section. One shared Dependencies/Milestone/Rollout/Conclusion at the end, never duplicated per
   area.
6. **Dependencies** — from analysis §3 (Affected repos & surfaces) — every analysis doc's §3 if
   there are several, merged into one Dependencies section (mirrors how `/pw-breakdown` merges
   every analysis doc into one PLAN).
7. **Milestone** — from `task/PLAN.md`'s dependency-DAG groups + task table + timeline estimate,
   filled at Wave 2. **Ask the human first** whether they want Milestone detail in the RFC at all
   before writing it — some RFCs are meant to stop at "here's the approved design," not expose the
   internal task breakdown. Only fill it after an explicit yes.
8. **Rollout Plan / Rollback Plan** — still only-if-asked (existing Wave 1 rule), but check analysis
   §4 first: an option's own Trade-offs/Design often already has deploy/rollout reasoning (staged
   rollout, feature-flag defaults, a migration plan) — draw from that rather than starting blank.
9. **Conclusion** — from task detail, filled at Wave 2 once analysis is approved and tasks exist —
   the recommendation restated for a reader who skipped straight here.
10. **References** — the links actually used, pulled from `context/INDEX.md`'s Source column (not
    every row necessarily — only what's genuinely worth pointing an outside reader at).
11. **Template hygiene** — before publishing, confirm no section still shows example-flavored filler
    text instead of a bare placeholder — `template/rfc/_TEMPLATE-RFC.md` should already be a clean
    skeleton; if you spot leftover example prose there, fix the template, not just this one doc.

## What this skill does NOT cover

Backend selection, target resolution, the section→real-heading mapping (`fetch_anchors`),
section-scoped external writes, callout/placeholder replacement, Pros/Cons-table fill, and the
markdown-hygiene rules (never split `**bold**` across a `` `code` `` span) — all in
[`tooling/docs/rfc.md`](../../docs/rfc.md)'s "Doc hygiene" section and
[`tooling/docs/rfc-backends.md`](../../docs/rfc-backends.md)'s per-backend rows. Diagram generation
(isolated sub-agent, mermaid, degrade-to-placeholder on failure) — `rfc.md`'s Diagrams section. The
comment-pull loop (`/pw-rfc … comments`) — same file, "Comment loop" section.

## Full context

[`docs/RFC.md`](../../../docs/RFC.md) (human-facing guide + worked walkthrough) ·
[`tooling/docs/rfc.md`](../../docs/rfc.md) (policy + canonical schema + hygiene rules) ·
[`tooling/docs/rfc-backends.md`](../../docs/rfc-backends.md) (backend registry) ·
[`template/rfc/_TEMPLATE-RFC.md`](../../../template/rfc/_TEMPLATE-RFC.md) (the literal skeleton) ·
the `project-workflow` skill (the pipeline this feeds into, if you have access to it).
