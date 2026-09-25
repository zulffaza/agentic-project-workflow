# Boundary & docs — what may leak to users, and how docs/plans are kept

Canonical: the **D-rules** in
[`tooling/docs/conventions.md`](../../../docs/conventions.md) §"D-rules — doc layers & issue routing",
and the information-boundary section of [`tooling/AGENTS.md`](../../../AGENTS.md). This page teaches the
two most-missed rules and routes to the owners.

## The information boundary (the T4-enforced floor)

- **User layer** = bundle-root `docs/`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `ONBOARDING.md`, and
  `template/`. It describes **behavior, never mechanics**. Four greps in `tooling/tests/static.sh`
  run on every harness: user docs carry **no automation-script names** (ONBOARDING.md is now in
  scope — its absence from the old file list is how ~12 mechanics lines hid there), and the user
  layer carries **no `tooling/` references at all** (strict D3, exemptions below).
- **Maintainer layer** = `tooling/docs/`. It carries mechanism detail, dated records, and the
  backlog. `tooling/docs/` may link *into* the user layer; the user layer never links back.
- **The one exemption by design:** `docs/TOOLING.md` is the single user-layer hub that pins where
  machinery docs live — the owner's "curiosity has one address" rule. New user-facing mechanism
  pointers go **there**, never scattered through guides and templates. Nothing else is exempt:
  root `AGENTS.md` is a pure user file (the maintainer-handoff lines were removed the same day as
  the sweep — owner decision), and maintainers onboard via `tooling/AGENTS.md` directly, the
  per-directory AGENTS.md convention. The audience-split doctrine canary now *forbids* any
  `tooling/` ref in the user entry point (`mutations.tsv` row `C76-…` pins it).

## The two gotchas (learned the hard way — teach these first)

1. **Self-contained terminology.** A shipped doc must read **without the plan that produced it**. A
   term is either self-explanatory, defined in place, or linked to its canonical definer — never a
   plan-local abbreviation (a rule label like `D9`, a bare tier/task ref, a `rev x`). User-layer
   docs carry **no** maintainer jargon at all. (This skill is maintainer-facing and unshipped, so it
   may *name* rules — but it still defines each in place. Eat the dog food.)
2. **Self-contained user layer (this is D3, strict form).** The user layer never links to, names,
   or instructs a read of anything under `tooling/` — except the hub above. A user must be
   able to act without ever opening a maintainer doc; if a user entry needs a "why", give it one
   line of cause inline, not a deep link. Where the user *behaviorally* needs mechanism detail
   (routing ladder, seed contract, effort mapping), ship a **registered twin** (D5): user-voice
   version in `docs/`, mechanics in `tooling/docs/`, pair listed in the duplication registry in
   `conventions.md` — twins drift silently unless they're written down.

**Enforcement status — what's mechanical vs doctrine-only (re-grounded 2026-09-25 after the
boundary sweep cleared the legacy set):**
- *Gotcha 1:* partially canaried. T4 greps `plan NN` (incl. hyphen/plural forms) and `KI-n` across
  all published files **including** `tooling/docs/`, root `*.md`, and `template/`
  (`mutations.tsv` row `C74-…` pins it). Rule labels / tier refs / `rev x` are **still not
  canaried** — `T01`…`T0n` are legitimate task IDs all over user docs, so a naive `T[0-9]`/`D[0-9]`
  grep false-positives; this skill remains the prevention layer for those, and a future canary must
  use a narrow pattern that can't match task IDs.
- *Gotcha 2:* now canaried, twice over. The user-layer machinery-refs grep (hub-only exemption) is
  pinned by `mutations.tsv` row `C73-…`, and the audience-split canary pins a tooling-free root
  `AGENTS.md` (`C76-…`) — re-adding a `tooling/` link or a maintainer handoff to a user doc fails
  T4. The
  ~48-line legacy set it used to tolerate was swept 2026-09-25; the dated record lives in
  `conventions.md` §Dated records.

## Issue routing (D2) — where a finding goes

| Finding | Destination |
|---|---|
| Symptom a user can hit in their workflow, with an action to take | `docs/TROUBLESHOOTING.md` (user voice, "what do I do right now") |
| Unfixed defect needing a bundle change | [`tooling/docs/known-issues.md`](../../../docs/known-issues.md) — the maintainer backlog (dated, `file:line` evidence, fix-plan pointer) |
| Settled gotcha whose mitigation is built in | the **mechanism-owning** doc under `tooling/docs/` as a dated *Mitigation (built in)* record |
| Superseded design record | delete — the owning doc carries current design; history is the EverOS KB's job (SoT) |

When a backlog entry's fix lands, it **moves** to the mechanism-owning doc as a dated record
(symptom + root cause + fix date preserved — records move between layers, they never shorten).

## Plan discipline (this hub)

Bundle improvements are tracked as `NN-*.md` plans in the hub's plans directory, indexed by a
`README.md`, each with a Status/Rev header and an append-only Status log (hub rule
`rules/PLAN_DOCS.md`; the index's own rules govern rows, timestamps, and result cells). **A plan is
single-use** — anything it decides that must outlive it gets written into the owning bundle doc
(that's gotcha 1), never left as a plan-local term. Don't rewrite plan history: record results in a
result file or a new log row, and fix a stale header rather than forking a third value.
