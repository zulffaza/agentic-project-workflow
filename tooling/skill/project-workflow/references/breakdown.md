# Breakdown phase (`/pw-breakdown`)

**Pre-flight first (scripts, not reasoning):**
`{{PW_HOME}}/tooling/pw-preflight.sh breakdown <slug> || exit 1` and
`{{PW_HOME}}/tooling/pw-doc-lint.sh analysis <slug> --all || exit 1`. `/pw-breakdown` runs these
already; when reached without it, run them yourself — a nonzero exit means STOP and relay stderr
(it names the unapproved gate or broken doc), don't reason onward to a PLAN nobody approved.

Asked to break analysis into tasks — refuses unless **every** real `analysis/<topic>.md`'s review
file has an `approved` sign-off (see `references/review.md`) — a project may have more than one
analysis doc (large, mostly-independent solution areas analyzed separately; see the analysis
template's "MULTIPLE LARGE SOLUTION AREAS" note). Once all are approved, produce **ONE merged**
PLAN + task set spanning every analysis doc — never one PLAN per doc:

1. **`task/PLAN.md`** (from `_TEMPLATE-orchestration-plan.md`) — repo manifest, global rules,
   **Produced by** (the provider this breakdown ran under = default execution provider), the
   dependency DAG, and the task table. **This is what the executor reads first.**
2b. **Writer lane (optional, seeded — refs/execution-and-routing.md §Spawn lanes).** When tasks are
   independent documents you may spawn `pw-writer-task` **once per task** with the caller's decisions
   (repo/base, boundary, landing unit, `Execute with:`+Why, SP, Verify expectations) as its seed —
   parallelizable because writers touch different files; **you** keep the decisions, the plan DAG,
   every gate and ledger line, and you exit-check each drafted file against its brief (gaps come
   back as a seed patch on the writer's logged id, not a re-draft). A writer must leave a
   `Model used:` line so the lane row's binding is auditable.
2. **`task/T01.md … Tnn.md`** (from `_TEMPLATE-task.md`) — each **self-contained** (one repo, one
   branch, one worktree, linked context, a runnable `## Verify` block = its Definition of Done).
   Write **DETAILED `## Steps`** (exact file + exact change + exact command per step) so the
   executor needs minimal independent reasoning — cheaper, more reliable. **The only thinking left
   to the executor is debugging why a given step didn't work, never deciding what a step should
   do.** Once Steps would run past ~8-10 flat items, split into named `### A.`/`### B.`/… phase
   sub-headings with continuous numbering (see `_TEMPLATE-task.md`'s sub-sectioning note). **Default
   each task's provider to "Produced by"** so the human isn't forced to switch agents; only route
   elsewhere with a `Why:`. See `references/execution-and-routing.md` for the full
    model/provider-routing rules that apply when filling in `Execute with:`.

**Task boundary rules — one task = one independently shippable MR.** An MR must be mergeable alone
with the system staying coherent; if a piece is meaningless without a sibling MR, it's the SAME task
(use `### A./### B./…` sub-phases), or — only when repos force separate worktrees — an explicit
**landing unit**. Split only on an independently-shippable seam (different repo; a feature-flagged /
backward-compatible increment valuable alone; a raw review-size ceiling on a single unit). Never
split by internal mechanics ("one task per pipeline step / file / module / endpoint") — that's how
one logical change becomes several interdependent MRs nobody can review alone. A must-land-together
set gets one shared `Landing unit: <name>` across its task files + a `## Landing units` note in
PLAN; ship records it in each MR description so the set is reviewed as one unit.

**Last step, mandatory:** `pw-lib.sh status <slug> breakdown` + a `pw-lib.sh log` line (see
`references/conventions-and-gotchas.md`). Remind the human that **only the PLAN sign-off gates
execution** — per-task reviews (`task/review/T0n.review.md`) are optional, created on demand.


## Lane spawn (optional — see references/execution-and-routing.md §Spawn lanes)

Once **your** decisions are fixed (manifest, DAG, boundaries, per-task `Execute with:`/`Why:`/SP),
task-file *drafting* can be delegated: spawn **`pw-writer-task`** with that task's decisions as its
brief (`seed-task` = task file + PLAN rows + the `## Verify` shape). Independent task docs batch in
parallel — different files, no shared-state race — capped by PLAN's `- Max parallelism:`; model from the
`AI Models: writer-task=` row. It returns the drafted docs + `Model used:`; **you** still fill the
judgment-bearing fields you own, run the gates/checks, write `PLAN.md`'s tables yourself, and
review-init. Spawn-less fallback = headless session or canonical body as prompt (§Spawn lanes).
