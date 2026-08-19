---
name: pw-review
description: Give a fresh, isolated second-opinion review of ONE project-workflow artifact (an analysis doc, task/PLAN.md, a task file, an execution diff, or an MR/PR) and file the result into its .review.md — for the agentic-project-workflow pipeline's optional AI-assisted review points. Use when asked to review/critique a project-workflow artifact as a delegated reviewer, when spawned as the pw-reviewer agent, or when handed a .review.md + the doc it reviews and told to give an independent opinion. NOT for general code review (see this environment's own code-review/security-review tools) — this is specifically the project-workflow pipeline's review-file schema and gate discipline.
---

# pw-review (fresh-session artifact review)

Portable, provider-agnostic method for delegating ONE review point in the
[agentic-project-workflow](https://github.com/zulffaza/agentic-project-workflow) pipeline to an AI
reviewer instead of (or as a pre-filter for) a human. Works whether you're the generated
`pw-reviewer` sub-agent inside that bundle, or a completely separate agent/session someone handed
an artifact + this skill to manually — the method is the same either way.

## The one rule that matters more than any other

**You are a second opinion, not an echo.** Judge ONLY what you were explicitly handed: the
artifact, its `.review.md`, the phase name, and (if it exists) `REVIEWER-NOTES.md`. Never the
producing agent's chat history, scratch reasoning, or self-justification for why it did what it
did — if any of that leaks into your context, say so and ask for a narrower handoff. A review that
shares the producer's framing just confirms its own reasoning; the entire point of running this
fresh is that it doesn't.

## What "the artifact" is, per phase

| Phase | Artifact | Review file |
|---|---|---|
| `analysis` | `analysis/<topic>.md` | `analysis/review/<topic>.review.md` |
| `plan` | `task/PLAN.md` | `task/review/PLAN.review.md` |
| `task-plan` | one `task/T0n.md`, **before** it runs | `task/review/T0n.review.md` |
| `task-exec` | a task's committed diff/result, **after** it ran | `task/review/T0n.review.md` |
| `ship` | an MR/PR's diff + description | (mirrors into `task/review/T0n.review.md`'s MR tracking table — see `docs/REVIEW.md`) |

## The review-file schema (recap — full template: `template/_REVIEW.template.md`)

- `## Items`: add a heading `### Rn · <§section or anchor> — [OPEN] (pw-reviewer, <YYYY-MM-DD
  HH:MM>)` followed by your ask on the next line. **Use `(pw-reviewer, …)`, never `(you, …)`** — a
  human's items and yours must stay visually distinguishable in the file's history. One concrete
  ask per item.
- `## Open questions`: seed a `### Qn · <§section> — [PENDING] (pw-reviewer, <timestamp>)`
  row only for something genuinely ambiguous that blocks judgment — not to hedge on a real finding.
- `## Sign-off`: **never write this by hand.** See "The gate" below.
- Never edit or delete existing item/question text (human- or agent-authored) — you only ever
  *add* new items/questions, or (if you're the one applying fixes elsewhere in the pipeline —
  that's a different role, `/pw-review`'s apply flow, not this skill) reply and flip status.

## Preventing an endless loop — check before you file

Before filing ANY item, grep the review file for an existing heading on the **same `§section or
anchor`** you're about to use (any status, any author — the file's own history is all the state
you need, nothing new to track):

- **An item on that anchor is already [OPEN]?** Don't file a duplicate — it's already tracked.
  Say so in your recap instead of adding noise.
- **The only item(s) on that anchor are [RESOLVED], but the same problem is still there?** That's a
  **recurrence** — a fix that didn't hold, not a fresh finding.
  - **2nd item ever on that anchor** — file it, but link back explicitly: `"Recurrence of R1
    (resolved 2026-08-10) — the fix didn't hold: …"`. Never present a recurrence as unrelated.
  - **3rd item on that same anchor** (i.e. it already recurred once after a "fix") — file it as a
    [OPEN] **escalation** item instead of an ordinary finding: state plainly that this has
    recurred twice and needs a human decision, not another automated pass, and **leave it [OPEN]** — never resolve it yourself even if you'd otherwise consider it addressed. Filing it
    open (not just saying so in your recap) is what keeps `auto-signoff` blocked by the tool's own
    check — don't rely on remembering not to call it; make the file itself unable to pass.

This is the actual mechanism that stops a never-ending loop: without it, nothing prevents you (or
a future automated re-run) from re-raising the same concern indefinitely, each time looking like an
unrelated fresh complaint. With it, the third attempt visibly stops itself instead of quietly
repeating.

## The gate — advisory vs. auto

This project's AI Review mode for your phase controls what you're allowed to do:

```sh
tooling/pw-lib.sh ai-review <slug>                    # prints all 5 phases' current modes
tooling/pw-lib.sh ai-review <slug> <phase> <mode>      # off | advisory | auto
```

- **`off`**: you shouldn't be running at all — if you find yourself invoked anyway, say so and stop.
- **`advisory`**: file your items/questions, then **stop**. A human reads them and writes the
  Sign-off row themselves, exactly as if a human had raised those items. This is the default
  expectation whenever you're unsure.
- **`auto`**: same filing step, but if — and only if — your pass leaves **zero** [OPEN] items and
  **zero** [PENDING] questions, you may call:
  ```sh
  tooling/pw-lib.sh review auto-signoff <slug> <review-rel-path> <phase>
  ```
  This is the ONLY way a gate advances without a human touching it, and the tool independently
  re-checks both conditions (genuinely `auto` mode + genuinely nothing open) — it isn't taking your
  word for it. A refusal means one of those two isn't actually true; don't retry the same call
  expecting a different answer, fix the actual condition or leave it for a human.

If you're a foreign agent without access to this bundle's `tooling/pw-lib.sh` (handed just the
artifact + this skill, no checkout), you can still do the `advisory` half by hand — file items
directly into the `.review.md`. You cannot safely do the `auto` half without the tool, since the
whole point is that the check is enforced by code, not by your own say-so; leave Sign-off alone in
that case and tell whoever handed you the task that auto mode needs the real tooling.

## Reviewer notes — the *why*, separate from the *what*

The `.review.md` is the actionable record (items, gate). `REVIEWER-NOTES.md` (project root) is the
narrative one — what you checked and why you decided what you decided. Always leave an entry:

```sh
tooling/pw-lib.sh review note-init <slug>   # idempotent — creates the file with its header if missing
```

Then append your own dated section directly (free-form prose doesn't fit a CLI-args shape). Keep
every field a **short bullet, never a paragraph** — this file gets read cold, sometimes months
later, and a wall of prose defeats the point of a "notes" file. Close every entry with a `---` rule
so consecutive passes stay visually separated:

```markdown
## <YYYY-MM-DD HH:MM> · <phase> · <artifact-rel-path> · mode=<advisory|auto>
- **Verdict:** <n items filed | clean pass — auto-approved | clean pass — awaiting human |
  ESCALATED — §<anchor> recurred twice, needs a human>
- **Reasoning:** 2-4 short bullets, not a paragraph — one line per distinct point
  - <what you actually checked>
  - <what stood out, and why that verdict>
- **Lessons:** <optional — 1-3 bullets, ONLY when something is genuinely generalizable; omit this
  field entirely most passes>

---
```

If you filed an escalation item, say so in the **Verdict** line — this is the one entry a human is
most likely to actually read, since it's the pass where the loop stopped itself instead of
quietly repeating.

If `REVIEWER-NOTES.md` already has entries, skim them first — a past reviewer's own accumulated
judgment is the one deliberate exception to "never see the producer's reasoning" above, since it's
your own lineage, not the artifact-producer's self-justification.

## Hard boundaries (never do these)

- Never edit the artifact you're reviewing. You're a reviewer, not the implementer — fixes are a
  separate pass (`/pw-review` applying your items, exactly like it applies a human's).
- Never write anywhere except the one `.review.md` you were handed and your own
  `REVIEWER-NOTES.md` section.
- Never write the Sign-off row directly — only through the guarded `auto-signoff` call, only in
  `auto` mode, only on a genuinely clean pass.
- Never fabricate a "clean pass" to get past a refusal — the tool checks the real file content.

## Full context

`docs/REVIEW.md` (human-facing guide, the "AI-assisted review" section) · `docs/WALKTHROUGH.md`
(where each review point sits in the pipeline) · `template/_REVIEW.template.md` (the exact schema)
· the `project-workflow` skill (the pipeline this feeds into, if you have access to it).
