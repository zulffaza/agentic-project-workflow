# Boundary & docs — what may leak to users, and how docs/plans are kept

Canonical: the **D-rules** in
[`tooling/docs/conventions.md`](../../../docs/conventions.md) §"D-rules — doc layers & issue routing",
and the information-boundary section of [`tooling/AGENTS.md`](../../../AGENTS.md). This page teaches the
two most-missed rules and routes to the owners.

## The information boundary (the T4-enforced floor)

- **User layer** = bundle-root `docs/`, `README.md`, `AGENTS.md`, and `template/`. It describes
  **behavior, never mechanics**. Two greps in `tooling/tests/static.sh` enforce this on every harness
  run: user docs carry **no automation-script names**, and published files carry **no `plan NN`
  references**.
- **Maintainer layer** = `tooling/docs/`. It carries mechanism detail, dated records, and the
  backlog. `tooling/docs/` may link *into* the user layer; the user layer never links back.

## The two gotchas (learned the hard way — teach these first)

1. **Self-contained terminology.** A shipped doc must read **without the plan that produced it**. A
   term is either self-explanatory, defined in place, or linked to its canonical definer — never a
   plan-local abbreviation (a rule label like `D9`, a bare tier/task ref, a `rev x`). User-layer docs
   carry **no** maintainer jargon at all. (This skill is maintainer-facing and unshipped, so it may
   *name* rules — but it still defines each in place. Eat the dog food.)
2. **Self-contained user layer (this is D3).** `docs/`, `template/`, and root `README.md`/`AGENTS.md`
   **never** link to or name `tooling/` internals. A user must be able to act without ever opening a
   maintainer doc; if a user entry needs a "why", give it one line of cause inline, not a deep link.

**Enforcement status — be honest about what is mechanical vs doctrine-only:**
- *Gotcha 1:* T4 greps `plan NN`, but **not** rule labels / tier refs / `rev x`. The tokens are
  ambiguous — `T01`…`T0n` are legitimate **task IDs** all over user docs — so a naive `T[0-9]` /
  `D[0-9]` grep false-positives on real content. No canary today; this skill is the prevention
  layer. A future narrow canary (e.g. rule-label `D[0-9]` in user docs, excluding `conventions.md`)
  must never match task IDs.
- *Gotcha 2:* D3 is doctrine + backlog only. A `tooling/`-ref canary can be minted **once the legacy
  set is cleared** — the ~12 pre-D3 pointers are tracked in
  [`tooling/docs/known-issues.md`](../../../docs/known-issues.md). Standing rule until then: **add no
  new ones.**

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
