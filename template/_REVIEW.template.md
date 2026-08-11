# Review: <doc.md>

Reviewing: [<doc.md>](../<doc.md>)
Gate: in-review

<!--
WHERE THIS LIVES — review files sit in a `review/` subdir next to the doc they review:
  analysis/<topic>.md      → analysis/review/<topic>.review.md
  task/PLAN.md             → task/review/PLAN.review.md
  task/T0n.md              → task/review/T0n.review.md
So the "Reviewing:" link above points one level up (../) to the reviewed doc.

HOW THIS FILE WORKS — read before editing.
- YOU (human) write review items below. Agents must NEVER edit or delete your item text.
- If this project's AI Review mode (dashboard `AI Review:` line, see docs/REVIEW.md) is
  `advisory`/`auto` for this phase, the `pw-reviewer` agent may ALSO write items here — tagged
  `(pw-reviewer, <timestamp>)`, never `(you, …)`, so it's always visually distinct from a human
  item in this file's history. Treat a `pw-reviewer` item exactly like a human one when applying it.
- To address an item, the agent appends a "↳ agent:" reply and flips 🔴 open → 🟢 resolved.
  That reply is the agent's summary of what it did — it must be concrete (name the section and
  what changed), never a bare "fixed"/"done". No diff needed; the summary is the record.
- After a pass, the agent also recaps the resolved items back in chat, so you see what it did
  without opening the file.
- Anchor each item to a section of the doc (§heading), because the doc itself gets rewritten
  when fixes are applied — this file is the durable record, the doc is not.
- Only YOU fill the Sign-off table by hand. The ONE exception: with this phase's AI Review mode
  set to `auto`, `pw-reviewer` may write a row itself — via the guarded `pw-lib.sh review
  auto-signoff` (which refuses unless mode is genuinely `auto` AND nothing here is still
  🔴 open/⏳ awaiting answer), never by hand-editing this table. That row's "By" column always
  reads `pw-reviewer (auto)`, never blended with a human "you" row — see docs/REVIEW.md.
- List everything still open in a project:  grep -rln "🔴 open" .
- **Every item/question heading carries a trailing `<!-- pw-item-status: open|resolved -->`
  machine marker, alongside the human-facing 🔴/🟢/⏳/✅ text — don't remove it when you flip a
  status, update BOTH together.** This is what tooling (the auto-signoff gate check) actually
  keys off; the emoji stays purely for human skimming. Keeps the gate check robust even if this
  template's wording/emoji ever changes later — see docs/KNOWN-ISSUES.md's template-gotcha entry
  for why this exists.
- **Agents:** the `> **Add an item:**` / `> **Answer a question:**` blockquotes right under
  "## Items" / "## Open questions" are a PERMANENT syntax reference, not the deletable worked
  example below — never remove them, even when clearing a section down to "No blocking …". Create
  this file via `pw-lib.sh review-init <slug> <review-rel-path> <doc-rel-path>` (copies this
  template verbatim) rather than hand-writing one, so nothing here gets silently dropped.
-->

## Decision status — what moves, and who moves it
Two independent dials. Don't confuse them:

| Dial | Values | Who sets it |
|------|--------|-------------|
| **Per-item status** (each `Rn`) | `🔴 open` → `🟢 resolved` | 🤖 agent flips it after addressing your item. You never set this. |
| **Per-question status** (each `Qn`) | `⏳ awaiting answer` → `✅ answered` | 🤖 agent flips it once it folds in your `↳ you:` answer. |
| **Gate decision** (Sign-off table) | `in-review` · `changes-requested` · `approved ✅` | 🧑 **you only.** This is the dial that actually opens the next phase. |

**So after you write review items, you do NOT set any item status** — you just leave them `🔴 open`
and run `/pw-review`; the agent resolves them. The only status *you* decide is the **gate**, in the
Sign-off table: add an `approved ✅` row when you're satisfied (that unlocks the next phase), or a
`changes-requested` row to send it back for another pass.

**Filled by:** [🧑 you] write Items + Open-question answers + the Sign-off (by hand). [🤖 agent]
appends `↳ agent:` replies, flips item/question status dots, and seeds Open-question rows when it
needs a decision. [🤖 pw-reviewer] — only if this phase's AI Review mode is `advisory`/`auto` —
writes Items the same way you would, tagged `(pw-reviewer, <timestamp>)`; in `auto` mode only, and
only via the guarded tool (never by hand), it may also write the Sign-off row. None of the three
edits another's text.

## Items

> **Add an item:** start a new heading `### Rn · <§section or anchor> — 🔴 open (you, <YYYY-MM-DD
> HH:MM>) <!-- pw-item-status: open -->`, then write your ask on the line below it. **Keep the
> trailing `<!-- pw-item-status: … -->` marker** — that's what the auto-signoff gate check
> actually reads, the emoji is for humans. An agent replies with a `  ↳ agent: …` line and flips
> your heading to `🟢 resolved (you, <timestamp>) <!-- pw-item-status: resolved -->` (both the
> emoji AND the marker, together) — it never edits or deletes your text otherwise. (This hint
> stays even once items exist or the section is emptied back to "No blocking …" — it's the syntax
> reference, not the worked example below.) If AI Review is `advisory`/`auto` for this phase,
> `pw-reviewer` writes items the same way, with `(pw-reviewer, <timestamp>)` in place of `(you, …)`.

<!-- ↓↓ WORKED EXAMPLE (delete this block once you get the idea) ↓↓
### R1 · §3 Affected repos — 🔴 open (you, 2026-08-06 10:20) [marker: pw-item-status open]
You listed `hera` as touched, but the Kafka toggle also lives in `common-config`. Add it to the
repo table and say whether it needs its own task.

  ↳ agent (2026-08-06 11:05): §3 — added a `common-config` row (config-only change); §7 — split
     the "rough shape" bullet into two chunks so breakdown can give it its own task. Item resolved.
### R1 · §3 Affected repos — 🟢 resolved (you, 2026-08-06 10:20) [marker: pw-item-status resolved]   ← agent flipped 🔴→🟢 AND the marker
↑↑ END EXAMPLE ↑↑ -->
<!-- NOTE for whoever edits this template: the two "[marker: ...]" tags just above are shown in
bracket notation, NOT the real `<!-- pw-item-status: ... -->` HTML-comment syntax, on PURPOSE —
this whole worked-example block is already wrapped in one outer HTML comment, and HTML comments
cannot nest. A real `<!-- pw-item-status: … -->` on those lines would prematurely close THIS
comment at its first `-->`, leaving the rest of the worked example unprotected and visible to the
gate check. The live headings below (outside any wrapping comment) DO use the real syntax. -->

### R1 · <§section or anchor> — 🔴 open (you, <YYYY-MM-DD HH:MM>) <!-- pw-item-status: open -->
<what needs to change, and why. One concrete ask per item — split unrelated asks into R2, R3…>

## Open questions (agent asks → you answer)
The agent seeds a `Qn` row here when it hits something it can't resolve (mirrors the analysis
doc's §5). **You answer** with a `↳ you:` line; the agent then folds the answer into the doc and
flips the row to ✅ answered. This is the QnA channel — don't answer inside the rewritten doc.

> **Answer a question:** under the `Qn` heading, add a line `  ↳ you (<YYYY-MM-DD HH:MM>): <your
> decision/answer>`. The agent folds it into the doc on the next pass and flips the row to ✅
> answered. (Permanent hint — stays even with no open questions.)

<!-- ↓↓ WORKED EXAMPLE ↓↓
### Q1 · §4 Approach — ⏳ awaiting answer (agent, 2026-08-06 09:50) [marker: pw-item-status open]
Toggle default: should the flag ship **off** (opt-in, safest) or **on** (parity with today)?
  ↳ you (2026-08-06 10:20): ship it OFF by default; we'll enable per-service after canary.
### Q1 · §4 Approach — ✅ answered (agent, 2026-08-06 11:05) [marker: pw-item-status resolved]   ← agent flips after folding in
  ↳ you (2026-08-06 10:20): ship it OFF by default; we'll enable per-service after canary.
  ↳ agent (2026-08-06 11:05): folded into §4 — default flag value = off; added a canary note to §5.
↑↑ END EXAMPLE ↑↑ -->
<!-- (Bracket notation used above, not the real HTML-comment marker syntax — same nesting reason
as the R-item worked example earlier in this file; see its note.) -->

### Q1 · <§section> — ⏳ awaiting answer (agent, <YYYY-MM-DD HH:MM>) <!-- pw-item-status: open -->
<the agent's question>
<!-- You answer by adding, under the question:
  ↳ you (<YYYY-MM-DD HH:MM>): <your decision/answer>   -->

## Sign-off  (human only — an agent never writes here)

This table is the **gate**. Add a row **when you're satisfied this phase is complete** — that
`approved ✅` row is what clears the gate for the next phase. Use date-time **to the minute**:
review rounds often happen the same day, so a bare date can't order them.

| Date-time (YYYY-MM-DD HH:MM) | By | Decision |
|------------------------------|-----|----------|
| | | in-review |

<!-- EXAMPLE of a cleared gate — your final row looks like:
| 2026-08-06 11:30 | you | approved ✅ |

Or, ONLY when this phase's AI Review mode is `auto` and pw-reviewer's own pass leaves nothing
open, `pw-lib.sh review auto-signoff` writes a row itself, tagged distinctly so it's never mistaken
for your approval:
| 2026-08-06 11:30 | pw-reviewer (auto) | approved ✅ |

- Not ready yet? Leave the `in-review` row, or add a `changes-requested` row and run /pw-review again.
- Reopening a phase later? Add a new "in-review" row (don't delete the old approval), bump the
  dashboard Status back with `pw-lib.sh status <slug> <phase> --rewind`, and re-run the phase.
  See README "Going back a phase". -->
