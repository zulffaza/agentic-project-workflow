---
name: pw-independent-review
description: Run a fresh, read-only second-opinion review of a raw commit/range/diff or a local/technical document, with NO project-workflow record writes — findings return in chat by default (or one explicitly authorized report file). Use when asked to independently review code or a document outside a scaffolded project (or without touching its review files), when handed a prepared review/ai packet to answer as report JSON, or when a second opinion is wanted without the pw-review pipeline schema. NOT for applying project-workflow review comments (that is the pw-review skill + /pw-review) and not a replacement for a human sign-off.
---

# pw-independent-review (standalone second opinion)

One fresh-context, READ-ONLY review of ONE target — a raw code change set (commit,
range, staged/unstaged, or an explicitly named diff) or a technical document — that writes NO
workflow records and touches no repository. The caller states the target and options; you return a
report. This skill is provider-agnostic; it works in any agent CLI.

## Hard rules

- **Read-only.** Never edit the target, its repository, any `.review.md`/`REVIEWER-NOTES.md`, or
  any workflow record. Never run commands that change repository or forge state (no checkout
  retargeting, no push, no comment, no labels, no merges). Finding a workflow project next to the
  target changes nothing here.
- **Fresh context.** Judge only the declared target, the declared criteria, and evidence you read
  from it. Never pull in the producing session's chat, a defense of the design, or hidden
  reasoning; if such material leaks into your context, say so and ask for a narrower handoff.
- **No workflow credit.** This review never approves anything, never satisfies a project gate, and
  never feeds `auto` outcomes. If the caller wants the result inside a project, they import the
  JSON against a prepared packet, where it stays advisory.
- **Honest coverage.** State exactly what you examined and what you did not (unread files,
  unavailable history, skipped generated code). An incomplete read is a finding's caveat, never a
  silent omission.

## Accept the request

The caller provides (in chat, or via a prepared `review/ai/<pass-id>/` packet):

| Input | Meaning |
|---|---|
| `kind` | `commit` · `range` · `working` (staged/unstaged/all) · `diff` (explicit patch file) · `document` |
| target | the commit/range/ref, patch path, or document path (plus `supporting=` for documents) |
| `packet` | optional: a prepared workflow packet — use its `request.md` criteria, its `snapshot/` copies, and its `pass_id`; do not re-freeze anything yourself |
| `output` | optional: omission means chat (human-readable); `json` returns the machine report in chat; an explicit absolute `.md`/`.json` path saves ONE report there |

For code targets, identify the exact reviewed identity: repository, each commit or range endpoint,
and (for `working`) the working-tree state description. For documents, the file digest.

## Do the review

Read the target end to end at the identity you declared — no shuffling under you; if anything
moves, say so and re-declare. Then judge with this order of proof:

1. **Correctness** — does it do the declared thing? Hunt the load-bearing paths first: error
   handling, boundary conditions, concurrency, resource lifetime, security-sensitive inputs
   (shell/SQL/HTML/deserialization/paths), and the diff's interaction surface with existing code.
2. **Evidence over vibes** — every finding cites the exact file/lines (or section) and why it is
   wrong, with a concrete failure or a precise ambiguity. No style nits without consequence, no
   "consider adding" lists.
3. **One correction per finding** — state the smallest correction you would accept; do not
   write a redesign.
4. **Questions, not guesses** — anything that needs a product decision or unavailable context goes
   into `questions`; never smuggle it in as a finding and never answer it yourself.
5. **Don't re-raise the known** — respect the supplied ledger/open findings; a previously resolved
   defect that recurred needs fresh evidence and names what it recurs from.

## Return the report

**Chat (default).** Verdict first, then findings ordered by severity, then coverage and gaps.
Keep each finding to: severity, location (file:line / section), what is wrong, evidence, the
requested correction. Close with what was NOT examined.

**`output=json` or a prepared packet** — emit exactly this shape (it is what the workflow
importer validates; ≤50 findings, ≤50 questions, ≤1 MB):

```json
{
  "schema": "pw-review-report/1",
  "pass_id": "<the packet's pass id, or the caller-supplied id>",
  "verdict": "clean | findings | blocked",
  "scope": "<exact reviewed target>",
  "coverage": ["what you examined", "honest gaps"],
  "findings": [
    {"key": "F1", "severity": "high|medium|low|info", "artifact": "<reviewed path>",
     "anchor": "§<section or file:line>", "issue": "…", "evidence": "…", "correction": "…",
     "recurrence_of": "R3"}
  ],
  "questions": [
    {"key": "Q1", "artifact": "<reviewed path>", "anchor": "§…", "question": "…"}
  ],
  "reviewer": {"provider": "<actual>", "model": "<actual, or unknown>"}
}
```

`verdict=clean` requires an EMPTY findings list and no judgment-blocking gap. Field values carry
no markdown headings and no HTML-comment syntax (the importer rejects them). Identify yourself
truthfully: name your actual provider/model when you know it; otherwise `unknown` — never a guess.

**Explicit file output.** Write the report to the ONE authorized path (the caller validated it is
outside the reviewed inputs and every workflow/project record), then confirm in chat with the exact
path, format, verdict, and coverage limits. Refuse — in chat — if the destination overlaps the
reviewed target, an existing report you were not told to replace, or an unwritable parent.

## Boundaries

- This skill writes no project records by itself. If the caller pastes your report into a project
  session without a prepared packet, it is ordinary feedback there — not a structured import.
- A prepared-packet report must carry that packet's `pass_id`; the importer rejects any other.
- Forge comments/replies are always the caller's separate, explicitly-authorized flow — never here.
