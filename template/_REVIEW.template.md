# Review: <doc.md>

Reviewing: [<doc.md>](../<doc.md>)
Gate: in-review

<!-- WHERE THIS LIVES: review files sit in a `review/` subdir next to the doc they review
  (analysis/<topic>.md → analysis/review/<topic>.review.md · task/PLAN.md → task/review/
  PLAN.review.md · task/T0n.md → task/review/T0n.review.md) — "Reviewing:" above points ../ to it.

QUICK REFERENCE (full mechanics + rationale: docs/REVIEW.md):
- You write items/answers below; the agent never edits or deletes your text, only replies.
- If AI Review is advisory/auto for this phase, `pw-reviewer` may also write items, tagged
  `(pw-reviewer, <timestamp>)` — treat exactly like your own.
- Agent replies `↳ agent: <concrete summary — section + what changed, never a bare "fixed">` and
  flips the status dot. It also recaps resolved items back in chat.
- Anchor each item to a §section — the doc gets rewritten on fixes, this file is the durable record.
- Only YOU write an `approved ✅` Sign-off row. Two narrow, distinctly-tagged tool exceptions exist
  (auto-signoff in `auto` mode; auto-reopen on analysis/PLAN post-approval) — see docs/REVIEW.md.
- List everything open in a project: `grep -rln "🔴 open" .`
- Every heading carries a trailing `<!-- pw-item-status: open|resolved -->` marker alongside the
  🔴/🟢/⏳/✅ text — flip both together. Tooling keys off the marker, not the emoji.
- **Agents:** the `> **Add an item:**` / `> **Answer a question:**` hints are permanent — never
  remove them, even once a section reads "No blocking …". Create this file via `pw-lib.sh
  review-init` (copies the template verbatim), never by hand. -->

## Decision status — what moves, and who moves it

| Dial | Values | Who sets it |
|------|--------|-------------|
| Item (`Rn`) | 🔴 open → 🟢 resolved | 🤖 agent, after addressing it |
| Question (`Qn`) | ⏳ awaiting answer → ✅ answered | 🤖 agent, after folding in your `↳ you:` |
| **Gate** (Sign-off) | in-review · changes-requested · **approved ✅** | 🧑 **you only** — opens the next phase |

You never set an item/question's own status — just leave items `🔴 open` and run `/pw-review`.

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
<!-- `[marker: ...]` above is a bracket stand-in, not real comment syntax — HTML comments can't
nest inside this wrapping one. See docs/KNOWN-ISSUES.md. Live headings below use the real syntax. -->

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
<!-- Same bracket-notation reason as the R-item example above. -->

### Q1 · <§section> — ⏳ awaiting answer (agent, <YYYY-MM-DD HH:MM>) <!-- pw-item-status: open -->
<the agent's question>
<!-- You answer by adding, under the question:
  ↳ you (<YYYY-MM-DD HH:MM>): <your decision/answer>   -->

## Sign-off  (human only — an agent never writes here)

This table is the **gate**. Add a row when you're satisfied this phase is complete — `approved ✅`
is what clears it for the next phase. Date-time **to the minute** (rounds often land same-day).

| Date-time (YYYY-MM-DD HH:MM) | By | Decision |
|------------------------------|-----|----------|
| | | in-review |

<!-- Your row: | 2026-08-06 11:30 | you | approved ✅ |
Two distinctly-tagged tool-written rows can also appear (full rationale: docs/REVIEW.md, docs/RFC.md):
| 2026-08-06 11:30 | pw-reviewer (auto) | approved ✅ |     ← AI Review mode=auto, clean pass
| 2026-08-06 14:10 | pw-review (auto-reopen) | in-review | ← a fix landed here post-approval
(auto-reopen only fires while this doc's phase is still the project's CURRENT phase; otherwise
/pw-review asks first, since a later phase may depend on the approval it would invalidate)

- Not ready yet? Leave `in-review`, or add `changes-requested` and run /pw-review again.
- Reopening BY HAND (your own decision, not the auto-reopen above)? Add a new "in-review" row
  (keep the old approval), `pw-lib.sh status <slug> <phase> --rewind`, re-run the phase — see
  README "Going back a phase". -->
