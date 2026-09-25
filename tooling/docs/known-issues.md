# Known issues — maintainer backlog

**Audience:** maintainers (human or agent) of this bundle. This is the ONLY "known issues" page —
there is deliberately no user-facing one (D4, [`conventions.md`](./conventions.md) D-rules).

**What belongs here:** an *unfixed* defect that needs a bundle change — dated, with evidence
(`file:line` or a run reference), its impact, and a fix-plan pointer when one exists. Routing for
everything else (D2):

| Finding | Goes to |
|---|---|
| Symptom a user can hit in their workflow, with an action to take | [`docs/TROUBLESHOOTING.md`](../../docs/TROUBLESHOOTING.md) (user layer, "what do I do right now") |
| Unfixed defect needing a code change | **this page** (backlog entry) |
| Settled gotcha whose mitigation is built in | the mechanism-owning doc under `tooling/docs/` — as a dated *Mitigation (built in)* / *Fixed* record (e.g. `scripts/review-and-context-editing.md` §Verified gotchas, `scripts/status-and-preflight.md`, `providers.md` §Verification notes, `forges.md`) |
| Superseded design record | deleted — current design lives in the owning doc; history is carried by the EverOS KB (SoT) |

**Lifecycle:** when a backlog entry's fix lands, the entry MOVES to the mechanism-owning doc as a
dated record (symptom + root cause + fix date — nothing shortened) and is removed here. This page
stays as short as the backlog is.

## Open backlog

_Empty._ The boundary-debt entry that lived here (pre-D3 user→`tooling/` deep links, ~48 lines
across docs/template/ONBOARDING) was swept 2026-09-25 and moved to its mechanism-owning doc as a
dated record: [`conventions.md`](./conventions.md) §Dated records (boundary). The three T4 greps
that now guard it are pinned in `tooling/tests/expectations/mutations.tsv`.
