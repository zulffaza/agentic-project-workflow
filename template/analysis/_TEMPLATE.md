# Analysis: <topic>

<!-- [🤖 agent] writes this whole doc. You don't edit it — you review via
     analysis/review/<topic>.review.md and approve there. Legend: 🤖 agent · 🧑 you.

     STYLE RULE — this doc must stay readable through many review rounds, not just the first one:
     §1–4 always read as the CURRENT, clean understanding, as if a first-time reader opened it
     today. On every fold-in, REWRITE the affected prose in place; never just append more text onto
     it, and never put an `(Rn)`/`(Qn)` tag in a §1–4 heading or sentence — that's exactly what
     turns a doc unreadable after 20+ rounds. Which review item drove a change, why an earlier
     decision got superseded, the "user asked X, we said Y" narration — none of that belongs in
     §1–4. It all goes in §5.1's Decisions log below, and the full verbatim history always lives in
     `analysis/review/<topic>.review.md` regardless — this doc never needs to be its own archive. -->

- **Status:** draft | in-review | approved
- **Author:** <agent/you>   **Provider:** <the agent/CLI this ran under, e.g. `kilo` / `claude`>
- **Date:** <YYYY-MM-DD HH:MM>  <!-- timestamp ONLY — never a changelog; a round's summary is a
     Decisions-log line (§5.1), not a Date-field essay -->
- **Context used:** <list the context/ files & INDEX rows this is based on — for any bare external
     URL (not a local copy), this means its FETCHED content, not just the citation; see §1's note>

## 1. Problem / goal
What are we trying to achieve, in one paragraph. Why now.
<!-- If context/INDEX.md has a row whose File/link is a bare external URL (a Jira ticket, a Lark/
     Confluence doc, etc.), FETCH it before writing this doc — WebFetch for a generic URL, or the
     matching platform skill (e.g. lark-doc/lark-wiki for a Lark link) for a platform-specific one
     — and cite what it actually said, not just the link. If fetching genuinely fails, say so
     explicitly in "Context used" above and ask rather than silently treating it as absent —
     especially if its Trust notes marks it authoritative (e.g. "Approved"). -->

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

## 5. Decisions, risks & open questions

### 5.1 Decisions log
One line per resolved review item — what was decided, one line of *why*, and which section it
landed in. **This is the ONLY place `Rn`/`Qn` IDs belong in this doc.** If a later decision
supersedes an earlier one, EDIT that earlier line to say so (or drop it if it's no longer worth
knowing) — don't leave stale reasoning scattered through §1–4. The full verbatim history is always
in `analysis/review/<topic>.review.md`, so this log only needs the one-line *gist*, not a transcript.
- <Rn/Qn>: <what was decided, one line of why> — see §<section>

### 5.2 Risks, unknowns & follow-ups
- Risk: … → mitigation …

### 5.3 Open questions (QnA)
Anything you couldn't resolve from `context/` + memory + the repos, or that needs a human call.
Give each a stable ID so the answer can be tracked. `Q0` (if §4 has 2+ options) is reserved for
"which approach?" and anchors to §4, not here — numbering below starts at `Q1` regardless:
- ❓ **Q1:** <the question, and why it blocks/affects the analysis> — _status: awaiting answer_
- ❓ **Q2:** <…> — _status: awaiting answer_

> **How this gets answered (QnA flow):** each open `Q` is also mirrored as an item in this doc's
> review file (`analysis/review/<topic>.review.md`, under "## Open questions"). You answer there
> with `↳ you: <answer>`; `/pw-review` then folds the answer cleanly into §1–4 (flips the Q to
> _answered_, adds exactly one line to §5.1's Decisions log — never a tag in §1–4 itself) and
> continues the analysis. Don't answer by editing this doc — it gets rewritten; the review file is
> the durable channel.

## 6. Out of scope
Explicitly what this work will NOT do.

## 7. Rough shape of the work
A first-cut list of the chunks (not yet formal tasks) — feeds step 4 breakdown.
- …
