# Analysis phase (`/pw-analyze`)

Asked to analyze `context/`:

1. **Search memory first — only if a memory tool is configured** (`PW_MEMORY`; see
   `tooling/docs/memory.md`) — fold in and cite what's relevant; skip silently if none configured.
2. Read everything in `context/` — **including fetching any bare external URL** in
   `context/INDEX.md` (a Jira ticket, a Lark/Confluence doc, etc.): `WebFetch` for a generic URL,
   or the matching platform skill (`lark-doc`/`lark-wiki` for Lark) for a platform-specific one.
   Cite what it **actually said**, not just the link — an unfetched citation isn't "used", and is
   especially wrong to leave unfetched when its Trust notes marks it authoritative. If fetching
   genuinely fails, say so explicitly and ask rather than silently proceeding as if it were absent.
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
4. **Last step, mandatory:** set the dashboard one-liner + Status via
   `pw-lib.sh oneliner <slug> "…"` then `pw-lib.sh status <slug> analysis` (see
   `references/conventions-and-gotchas.md` for the full helper contract).
5. Iterate with the human until approved — see `references/review.md` for how the review loop
   works (local `.review.md` file, QnA, the Sign-off gate).
