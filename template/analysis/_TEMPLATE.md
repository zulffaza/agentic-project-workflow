# Analysis: <topic>

<!-- [🤖 agent] writes this whole doc. You don't edit it — you review via
     analysis/review/<topic>.review.md and approve there. Legend: 🤖 agent · 🧑 you. -->

- **Status:** draft | in-review | approved
- **Author:** <agent/you>   **Date:** <YYYY-MM-DD HH:MM>
- **Context used:** <list the context/ files & INDEX rows this is based on>

## 1. Problem / goal
What are we trying to achieve, in one paragraph. Why now.

## 2. Current state
How things work today in the affected area. Cite `repo/path:line` where helpful.

## 3. Affected repos & surfaces
This is the **confirmed** scope — verify each repo's *real* state (actual base branch, module
shape, real versions on that branch, not a parked feature branch) and reconcile against the
"Repos in scope" guess in `context/INDEX.md`. Call out any repo you added, dropped, or corrected.

| Repo | Area / files | Nature of change |
|------|--------------|------------------|
| | | |

## 4. Proposed approach
The recommended path. If there are alternatives, summarize them and say why this one wins
(don't bury a survey — give a recommendation).

## 5. Risks, unknowns & open questions
- Risk: … → mitigation …

**Open questions (QnA)** — anything you couldn't resolve from `context/` + memory + the repos, or
that needs a human call. Give each a stable ID so the answer can be tracked:
- ❓ **Q1:** <the question, and why it blocks/affects the analysis> — _status: awaiting answer_
- ❓ **Q2:** <…> — _status: awaiting answer_

> **How this gets answered (QnA flow):** each open `Q` is also mirrored as an item in this doc's
> review file (`analysis/review/<topic>.review.md`, under "## Open questions"). You answer there
> with `↳ you: <answer>`; `/pw-review` then folds the answer into this section (flips the Q to
> _answered_, cites the decision) and continues the analysis. Don't answer by editing this doc —
> it gets rewritten; the review file is the durable channel.

## 6. Out of scope
Explicitly what this work will NOT do.

## 7. Rough shape of the work
A first-cut list of the chunks (not yet formal tasks) — feeds step 4 breakdown.
- …
