# Analysis phase (`/pw-analyze`)

Asked to analyze `context/`:

1. **Search memory first — only if a memory tool is configured** (`PW_MEMORY`; see
   `tooling/docs/memory.md`) — fold in and cite what's relevant; skip silently if none configured.
2. Write `analysis/<topic>.md` from `analysis/_TEMPLATE.md` (record the authoring `Provider:`).
   Describe *what & why*, **confirmed** affected repos (verify real state on the actual base
   branch — not a stale/parked feature branch), risks, options + a recommendation. Do **not** cut
   tasks yet — that's breakdown's job (see `references/breakdown.md`).
3. **Last step, mandatory:** set the dashboard one-liner + Status via
   `pw-lib.sh oneliner <slug> "…"` then `pw-lib.sh status <slug> analysis` (see
   `references/conventions-and-gotchas.md` for the full helper contract).
4. Iterate with the human until approved — see `references/review.md` for how the review loop
   works (local `.review.md` file, QnA, the Sign-off gate).
