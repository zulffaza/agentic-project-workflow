# Analysis phase (`/pw-analyze`)

Asked to analyze `context/`:

1. **Search memory first — only if a memory tool is configured** (`PW_MEMORY`; see
   `tooling/docs/memory.md`) — fold in and cite what's relevant; skip silently if none configured.
2. Read everything in `context/` — **including fetching any bare external URL** in
   `context/INDEX.md`, in this precedence order: Jira (the `jira` CLI if installed, e.g. `jira
   issue view <KEY>`) → GitHub issue/PR (`gh issue view`/`gh pr view` if installed) → GitLab
   issue/MR (`glab issue view`/`glab mr view` if installed) → Lark (`lark-doc`/`lark-wiki` skill,
   unchanged) → `WebFetch` for anything else, or whenever the matching CLI isn't installed
   (optional enrichment, same as everywhere else — fall through, never fail because a CLI is
   missing). Cite what it **actually said**, not just the link — an unfetched citation isn't
   "used", and is especially wrong to leave unfetched when its Trust notes marks it authoritative.
   **If fetching genuinely fails: STOP — do not write the analysis doc at all**, unless `/pw-analyze`
   was invoked with `--ignore-fetch-errors`, in which case list that row in "Context used" as
   `<row> — NOT fetched (--ignore-fetch-errors); treat with reduced confidence` instead of silently
   proceeding as if it were absent.
3. Write `analysis/<topic>.md` from `analysis/_TEMPLATE.md` (record the authoring `Provider:`).
   Describe *what & why*, **confirmed** affected repos (verify real state on the actual base
   branch — not a stale/parked feature branch), **genuinely distinct approach options** (§4 — the
   human picks, don't converge to one recommendation), decisions/risks/open questions (§5). Do
   **not** cut tasks yet — that's breakdown's job (see `references/breakdown.md`).
   - **§1–4 always read as the current, clean understanding — never an archive.** No `(Rn)`/`(Qn)`
     tags in headings or prose there, no "supersedes"/"the user asked" narration, no changelog in
     `Date:` (timestamp only). That history belongs *only* in §5.1's Decisions log (one terse line
     per item) — the `.review.md` file already holds the full verbatim record. This is what keeps
     the doc readable after many review rounds instead of turning into a review-file transcript.
   - **§3/§4 stay organized as detail accumulates, not just untagged.** One distinct fact per
     (sub-)bullet, never a paragraph chaining several unrelated facts; a table cell holds a fact or
     two, not an essay. Fold new §4 depth into an existing `### 4.N` subsection where one already
     owns that topic, rather than always appending a new one — see the template's density-rule
     comment.
   - **Every option uses the template's FIXED four-slot skeleton** (Design / Per-repo impact /
     Trade-offs, under an intro paragraph) — never a new ad hoc heading; new depth goes into one of
     those three slots.
   - **Several large, mostly-independent problem areas in one project** → don't cram them into one
     flat §4 — see the template's "MULTIPLE LARGE SOLUTION AREAS" comment for named §4 groupings
     vs. a separate `analysis/<topic>.md` per area (a second `/pw-analyze <slug> <area>` run — no
     phase/workflow change, `references/breakdown.md` already merges every analysis doc present).
     **Concrete trigger, not a vibe:** once §4 would need a 5th option/area slot, or the doc
     crosses roughly 500–600 lines (`wc -l`), that's the signal to split.
   - **Keep a lightweight heading index current as you write** — each `§`/`###` heading mapped to
     a one-line gist, refreshed as a targeted single-line edit per changed section, never a full
     rebuild. Lets a later review pass jump straight to the section an item names.
   - **Opportunistically seed memory too — IF configured** (skip silently if `PW_MEMORY=none`): a
     genuinely durable, generalizable finding (not this project's own bookkeeping) gets seeded
     using its own §5.1 Decisions-log one-liner as the payload — never a separate authoring pass.
4. **Last step, mandatory:** set the dashboard one-liner + Status via
   `pw-lib.sh oneliner <slug> "…"` then `pw-lib.sh status <slug> analysis` (see
   `references/conventions-and-gotchas.md` for the full helper contract).
5. Iterate with the human until approved — see `references/review.md` for how the review loop
   works (local `.review.md` file, QnA, the Sign-off gate).
