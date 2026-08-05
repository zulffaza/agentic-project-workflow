# Review: <doc.md>

Reviewing: [<doc.md>](../<doc.md>)
Gate: in-review | changes-requested | approved

<!--
WHERE THIS LIVES — review files sit in a `review/` subdir next to the doc they review:
  analysis/<topic>.md      → analysis/review/<topic>.review.md
  task/PLAN.md             → task/review/PLAN.review.md
  task/T0n.md              → task/review/T0n.review.md
So the "Reviewing:" link above points one level up (../) to the reviewed doc.

HOW THIS FILE WORKS — read before editing.
- YOU (human) write review items below. Agents must NEVER edit or delete your item text.
- To address an item, the agent appends a "↳ agent:" reply and flips 🔴 open → 🟢 resolved.
  That reply is the agent's summary of what it did — it must be concrete (name the section and
  what changed), never a bare "fixed"/"done". No diff needed; the summary is the record.
- After a pass, the agent also recaps the resolved items back in chat, so you see what it did
  without opening the file.
- Anchor each item to a section of the doc (§heading), because the doc itself gets rewritten
  when fixes are applied — this file is the durable record, the doc is not.
- Only YOU fill the Sign-off table. An agent cannot self-approve a gate.
- List everything still open in a project:  rtk grep -rln "🔴 open" .
-->

**Filled by:** [🧑 you] write Items + Open-question answers + the Sign-off. [🤖 agent] appends
`↳ agent:` replies and flips status dots — and seeds Open-question rows (below) when it needs a
decision. Neither edits the other's text.

## Items

### R1 · <§section or anchor> — 🔴 open (you, <YYYY-MM-DD HH:MM>)
<what needs to change, and why>

<!-- After the agent addresses it, the item should read:

### R1 · <§section> — 🟢 resolved (you, <YYYY-MM-DD HH:MM>)
<your original comment, left untouched>
  ↳ agent (<YYYY-MM-DD HH:MM>): <concrete summary — which section + what changed. e.g.
     "§3: added a valas-service row; §4: noted its migration is gated on T02">
-->

## Open questions (agent asks → you answer)
The agent seeds a `Qn` row here when it hits something it can't resolve (mirrors the analysis
doc's §5). **You answer** with a `↳ you:` line; the agent then folds the answer into the doc and
flips the row to ✅ answered. This is the QnA channel — don't answer inside the rewritten doc.

### Q1 · <§section> — ⏳ awaiting answer (agent, <YYYY-MM-DD HH:MM>)
<the agent's question>
<!-- You answer by adding, under the question:
  ↳ you (<YYYY-MM-DD HH:MM>): <your decision/answer>
Then the agent, next /pw-review pass, folds it in and rewrites the line to:
### Q1 · <§section> — ✅ answered (agent, <YYYY-MM-DD HH:MM>)
  ↳ you (…): <your answer, untouched>
  ↳ agent (…): folded into §<n> — <what it changed based on your answer> -->

## Sign-off  (human only — an agent never writes here)

Add a row **when you're satisfied this phase is complete** — that `approved ✅` row is what clears
the gate for the next phase. Use date-time **to the minute**: review rounds often happen the same
day, so a bare date can't order them.

| Date-time (YYYY-MM-DD HH:MM) | By | Decision |
|------------------------------|-----|----------|
| | | in-review |

<!-- Add a row with "approved ✅" to clear the gate for the next phase.
     Reopening a phase later? Add a new "in-review" row (don't delete the old approval) and
     bump the dashboard Status back — see base/README.md "Going back a phase". -->
