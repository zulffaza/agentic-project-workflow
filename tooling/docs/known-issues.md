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

### Pre-D3 deep links from the user layer into `tooling/docs/` — filed 2026-09-25
- **Evidence:** `grep -rn 'tooling/docs' docs/ template/` — "full detail" pointers that predate
  the D3 self-contained-user-layer rule: `docs/EXECUTION.md` (:56, :71, :324 → providers.md),
  `docs/RFC.md` (:33, :192, :218), `docs/REVIEW.md` (:204 → forges.md), `docs/MEMORY.md` (:69),
  `docs/WALKTHROUGH.md` (:282), `template/task/_TEMPLATE-task.md` (:33),
  `template/task/_TEMPLATE-orchestration-plan.md` (:106, :131), `template/rfc/README.md` (:17);
  related class: `docs/WORKFLOW.md:146`, `docs/ADOPTION.md:117`, `docs/REVIEW.md:189` point into
  `tooling/commands/`.
- **Impact:** none functionally — the entries are accurate — but D3 says the user layer is
  self-contained, and these predate it. The three NEW record links plan 23 introduced
  (_REVIEW.template.md, REVIEW.md phantom-count note, TROUBLESHOOTING deep-dives) were removed
  the same day on owner review; this backlog covers only the legacy set.
- **Fix plan:** none yet — owner decision needed on a blanket tightening (inline the needed
  detail, or drop the pointers). Until then: add no new ones (D3); a T4 canary can be minted
  once the legacy set is cleared.
