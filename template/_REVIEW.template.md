# Review: <doc.md>

Reviewing: [<doc.md>](../<doc.md>)
Gate: see Sign-off

<!-- pw-contents:begin -->
## Contents   [agent-owned; refreshed automatically; do not edit]

| ID | Section / anchor | Status |
|----|-------------------|--------|
| _(none yet)_ | | |
<!-- pw-contents:end -->

<!-- WHERE THIS LIVES: review files sit in a `review/` subdir next to the doc they review
  (analysis/<topic>.md → analysis/review/<topic>.review.md · task/PLAN.md → task/review/
  PLAN.review.md · task/T0n.md → task/review/T0n.review.md) — "Reviewing:" above points ../ to it.

QUICK REFERENCE (full mechanics + rationale: docs/REVIEW.md):
- You write items/answers below; the agent never edits or deletes your text, only replies.
- If AI Review is advisory/auto for this phase, `pw-reviewer` may also write items, tagged
  `(pw-reviewer, <timestamp>)` — treat exactly like your own.
- **One heading per item/question, always.** Resolving one edits that SAME heading in place
  (flips the status tag + the trailing marker together) — it never adds a second heading for the
  same item. That's what keeps consecutive items visually distinct instead of running together.
- Replies are quoted `> ↳ **agent** (<timestamp>): <section + exactly what changed>` lines below
  the ask, never a bare "fixed"/"done" — and never a restatement of your ask (see below).
  R-items get only a `↳ agent:` reply; Q-items also carry your `↳ you:` line (real, new content).
- A `---` rule follows every item's full block (heading + ask + reply), before the next one starts.
- Anchor each item to a §section — the doc gets rewritten on fixes, this file is the durable record.
- Only YOU write an `approved` row (the one exception: AI `auto` mode's guarded pass). The workflow
  also records **operational rows** here — agent-attributed, never your decision:
  `pw-review (feedback)` when your first new item/answer queues a fresh cycle, `pw-review (repair)`
  when a pass starts on real open work, `pw-reviewer (advisory; provider=…, model=…)` /
  `pw-reviewer (auto; provider=…, model=…)` for independent AI passes. See docs/REVIEW.md.
- List everything open in a project: `grep -rln "\[OPEN\]" .` (or, more robustly, the actual
  machine marker: `grep -rln "pw-item-status: open" .`).
- Every heading carries a trailing `<!-- pw-item-status: open|resolved -->` marker alongside the
  `[OPEN]`/`[RESOLVED]`/`[PENDING]`/`[ANSWERED]` tag — flip both together. Tooling keys off the
  marker, not the tag text. **Status tags are plain, keyboard-typable brackets on purpose** — no
  symbol you have to hunt down and copy-paste.
- **The `## Contents` table above is agent-owned** — heading-text-anchored (never a line number, so
  it never goes stale on a rewrite) and refreshed automatically by every write that adds or resolves
  a heading. Applying ONE item only needs that item's own block + the section(s) `## Contents`
  (or the doc's own analysis) names — never the whole file.
- **Once several items pile up `[RESOLVED]`/`[ANSWERED]`**, the review pass moves them verbatim
  into a sibling `<topic>.archive.md`, leaving a pointer row in a `## Archived items` table
  (appears once anything's been archived). This never touches `[OPEN]`/`[PENDING]` headings or the
  Sign-off table — see docs/REVIEW.md. Keeps a long-lived review file from forcing every new round
  to re-read the whole resolved history just to apply one new item.
- **Agents:** the `> **Add an item:**` / `> **Answer a question:**` hints are permanent — never
  remove them, even once a section reads "No blocking …". Create this file with
  `/pw-review <slug> init <doc-path>` (copies the template verbatim) — or `/pw-review <slug>
  init-all` for the review files missing in the project's CURRENT phase — never by hand. -->

## Decision status — what moves, and who moves it

| Dial | Values | Who sets it |
|------|--------|-------------|
| Item (`Rn`) | `[OPEN]` → `[RESOLVED]` | 🤖 agent, after addressing it |
| Question (`Qn`) | `[PENDING]` → `[ANSWERED]` | 🤖 agent, after folding in your `↳ you:` |
| **Gate** (Sign-off) | in-review · changes-requested · **approved** | 🧑 **you approve** — only `approved` opens the next phase; 🤖 records `in-review`/`changes-requested` operational rows (and `approved` only in guarded AI `auto` mode) |

You never set an item/question's own status — just leave items `[OPEN]` and run `/pw-review`.

## Items

> **Add an item:** easiest is the deterministic operator — `/pw-review <slug> item <this-file>
> §4 <your ask, spaces and all>` (it writes the heading, timestamp, marker, `---` rule, and
> reindexes `## Contents` for you; a first new item after an `approved` row also records one
> `pw-review (feedback)` `in-review` row, so the old approval stops being the live decision).
> By hand instead: start a
> new heading `### Rn · <§section or anchor> — [OPEN] (you, <YYYY-MM-DD
> HH:MM>) <!-- pw-item-status: open -->`, then write your ask on the line(s) below it, followed by
> a `---` rule before the next item. **Keep the trailing `<!-- pw-item-status: … -->` marker** —
> that's what the gate checks actually read, the `[OPEN]`/`[RESOLVED]` tag is for
> humans. To resolve it, an agent edits this SAME heading in place — flips `[OPEN]`→`[RESOLVED]`
> and the marker together, **never adding a second heading** — then appends a quoted
> `> ↳ **agent** (<timestamp>): …` reply directly below your ask (one blank line between them).
> **R-items never get a `↳ you:` line** — your ask is already the item's own body text right
> above; restating it there is just noise. (This hint stays even once items exist or the section
> is emptied back to "No blocking …" — it's the syntax reference, not the worked example below.)
> If AI Review is `advisory`/`auto` for this phase, `pw-reviewer` writes items the same way, with
> `(pw-reviewer, <timestamp>)` in place of `(you, …)`.

<!-- ↓↓ WORKED EXAMPLE (delete this block once you get the idea) ↓↓
### R1 · §3 Affected repos — [RESOLVED] (you, 2026-08-06 10:20) [marker: pw-item-status resolved]
You listed `hera` as touched, but the Kafka toggle also lives in `common-config`. Add it to the
repo table and say whether it needs its own task.

> ↳ **agent** (2026-08-06 11:05): §3 — added a `common-config` row (config-only change).
> §7 — split the "rough shape" bullet into two chunks so breakdown can give it its own task.

---
Before it's resolved, this is the SAME heading reading `[OPEN] (you, 2026-08-06 10:20) [marker:
pw-item-status open]`, ending right after your ask — no reply yet. The agent edits this exact
heading in place once it resolves the item (flips the tag + marker, appends the reply below); it
never creates a second heading for the same item.
↑↑ END EXAMPLE ↑↑ -->
<!-- `[marker: ...]` above is a bracket stand-in, not real comment syntax — HTML comments can't
nest inside this wrapping one. Live headings below use the real syntax. -->

### R1 · <§section or anchor> — [OPEN] (you, <YYYY-MM-DD HH:MM>) <!-- pw-item-status: open -->
<what needs to change, and why. One concrete ask per item — split unrelated asks into R2, R3…>

---

## Open questions (agent asks → you answer)
The agent seeds a `Qn` row here when it hits something it can't resolve (mirrors the analysis
doc's §5). **You answer** with a `↳ you:` line; the agent then folds the answer into the doc and
flips the row to `[ANSWERED]`. This is the QnA channel — don't answer inside the rewritten doc.

> **Answer a question:** easiest is `/pw-review <slug> answer <this-file> Qn <your answer>`
> (it writes the styled `↳ you:` line under the question; a first answer after an `approved` row
> records the same `pw-review (feedback)` `in-review` row as a new item).
> By hand instead: under the `Qn` heading, add a quoted line `> ↳ **you** (<YYYY-MM-DD
> HH:MM>): <your decision/answer>`. The agent folds it into the doc on the next pass, appends its
> own `> ↳ **agent** (<timestamp>): …` line right after yours (same quoted block, one blank quoted
> line between the two), adds a `---` rule, and flips this SAME heading to `[ANSWERED]` — never a
> second heading. (Permanent hint — stays even with no open questions.)

<!-- ↓↓ WORKED EXAMPLE ↓↓
### Q1 · §4 Approach — [ANSWERED] (agent, 2026-08-06 09:50) [marker: pw-item-status resolved]
Toggle default: should the flag ship **off** (opt-in, safest) or **on** (parity with today)?

> ↳ **you** (2026-08-06 10:20): ship it OFF by default; we'll enable per-service after canary.
>
> ↳ **agent** (2026-08-06 11:05): folded into §4 — default flag value = off; added a canary note
> to §5.

---
Before you answer, this is the SAME heading reading `[PENDING] (agent, 2026-08-06 09:50) [marker:
pw-item-status open]` with just the question — no `↳` lines yet. You add your `↳ you:` line under
it (still `[PENDING]`); the agent later folds it in, appends its own `↳ agent:` line right after
yours, and flips this exact heading to `[ANSWERED]` — never a second heading.
↑↑ END EXAMPLE ↑↑ -->
<!-- Same bracket-notation reason as the R-item example above. -->

### Q1 · <§section> — [PENDING] (agent, <YYYY-MM-DD HH:MM>) <!-- pw-item-status: open -->
<the agent's question>
<!-- You answer by adding, under the question:
> ↳ **you** (<YYYY-MM-DD HH:MM>): <your decision/answer>   -->

---

## Sign-off  (you approve; the workflow records operational rows here)

This table is the **gate**. Add a row when you're satisfied this phase is complete — `approved`
is what clears it for the next phase. Date-time **to the minute** (rounds often land same-day);
new rows are stamped like `5 October 2026 11.30 WIB` and older formats stay readable.
Easiest: `/pw-review <slug> signoff <this-file> approved` — it stamps the date-time and appends
the row; **human-triggered only**, an agent never runs it on its own initiative. By hand: fill
the row below. An `in-review`/`changes-requested` row **you** record stands until you withdraw or
replace it — automatic operational rows never override an explicit human decision.

| Date-time | By | Decision |
|-----------|-----|----------|
| | | in-review |

<!-- Your row: | 5 October 2026 11.30 WIB | you | approved |
Agent-recorded OPERATIONAL rows also appear here — always attributed, never disguised as yours
(full rationale: docs/REVIEW.md, docs/RFC.md):
| 5 October 2026 11.45 WIB | pw-review (feedback) | in-review |          ← your first new item/answer after an approval
| 5 October 2026 11.50 WIB | pw-review (repair) | changes-requested |    ← a pass started on real open work
| 5 October 2026 14.10 WIB | pw-reviewer (auto; provider=kilo; model=glm-5.2) | approved |
    ← guarded AI `auto` mode on a clean pass — the ONLY agent-written `approved` row; `advisory`
      never approves, a human always signs advisory phases off
(Legacy rows — plain `pw-reviewer (auto)`, `pw-review (auto-reopen)`, older date formats — stay
readable exactly as history; repairing or reopening an EARLIER phase's gate asks you first.)

- Not ready yet? Leave `in-review`, or add `changes-requested` and run /pw-review again.
- Reopening BY HAND (your own decision, not the recorded operational rows above)? Add a new "in-review" row
  (keep the old approval), `/pw-status <slug> rewind <phase>`, re-run the phase — see
  README "Going back a phase".
- A review file written before this bundle's keyboard-typable-symbols migration may still show the
  legacy `approved ✅` (with a checkmark) — that's read exactly the same as `approved` by every
  gate; no need to rewrite an already-approved file just to drop the emoji. -->
