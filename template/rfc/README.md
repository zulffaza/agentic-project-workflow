# rfc/ — optional RFC-doc side-loop

Entirely optional. Nothing else in the pipeline reads or requires this directory — skip it if you
don't write RFCs for this project.

- **`RFC.md`** — doesn't exist until the first `/pw-rfc` run. **Generated always** (from approved
  `analysis/` for Wave 1, from an approved `task/PLAN.md` for Wave 2 — `/pw-rfc <slug> milestone`),
  regardless of whether you publish anywhere external. This file is the source of truth; publishing
  to a real doc platform is an *additional*, optional step layered on top.
- **`META.md`** — 🤖-owned via `pw-lib.sh rfc target|state` — never hand-edit. Tracks the publish
  backend, the external doc's target ref, last revision pushed, which wave(s) are published, and
  the comment-sync cursor.

RFC publishing never touches the dashboard `Status:` phase machine — it's a side-loop, gated by the
**existing** approval gates (analysis `approved ✅` for Wave 1, PLAN `approved ✅` for Wave 2). Full
guide: [`docs/RFC.md`](../../docs/RFC.md). Backend config: `PW_RFC_BACKEND` in `pw.config.sh` (see
[`tooling/rfc.md`](../../tooling/rfc.md) + [`tooling/rfc-backends.md`](../../tooling/rfc-backends.md)).
