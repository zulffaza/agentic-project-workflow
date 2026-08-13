# Analysis: <topic>

<!-- [🤖 agent] writes this whole doc. You don't edit it — you review via
     analysis/review/<topic>.review.md and approve there. Legend: 🤖 agent · 🧑 you. -->

- **Status:** draft | in-review | approved
- **Author:** <agent/you>   **Provider:** <the agent/CLI this ran under, e.g. `kilo` / `claude`>
- **Date:** <YYYY-MM-DD HH:MM>
- **Context used:** <list the context/ files & INDEX rows this is based on>

## 1. Problem / goal
What are we trying to achieve, in one paragraph. Why now.

## 2. Current state
How things work today in the affected area. Cite `repo/path:line` where helpful.

## 3. Affected repos & surfaces
This is the **confirmed** scope — verify each repo's *real* state (actual base branch, module
shape, real versions on that branch, not a parked feature branch) and reconcile against the
"Repos in scope" guess in `context/INDEX.md`. Call out any repo you added, dropped, or corrected.
**A repo may need changes on more than one base branch** (e.g. a fix on `master` and its port on
`spring3`) — give it **one row per base branch** and name the base in each row.

| Repo | Base branch | Area / files | Nature of change |
|------|-------------|--------------|------------------|
| | | | |

## 4. Approach options
Lay out **genuinely distinct options** — don't collapse to one recommendation; the human picks.
Each option needs enough detail to actually evaluate (what it is, how it works, the real
trade-off), not a one-line strawman sitting next to a fully-fleshed "real" answer. If there truly
is only one reasonable approach, say so explicitly and why the alternatives don't hold up — that's
fine, but it's the exception, not the default.

### Option A: <name>
<what it is, how it works>
- **Trade-offs:** <pros/cons — cost, risk, blast radius, how it ages>

### Option B: <name>
<…>
- **Trade-offs:** <…>

**Chosen approach:** _pending your review_
<!-- [🧑 you] pick via the review file's QnA (Q0, auto-seeded below when 2+ options exist) —
don't edit this line directly, /pw-review fills it in once you answer. Breakdown reads ONLY the
chosen option; the others stay here as record, never implemented. -->

## 5. Risks, unknowns & open questions
- Risk: … → mitigation …

**Open questions (QnA)** — anything you couldn't resolve from `context/` + memory + the repos, or
that needs a human call. Give each a stable ID so the answer can be tracked. `Q0` (if §4 has 2+
options) is reserved for "which approach?" and anchors to §4, not here — numbering below starts
at `Q1` regardless:
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
