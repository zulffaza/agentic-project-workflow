---
description: Optional side-loop — publish approved analysis/plan content to an RFC doc (any configured backend, or a local-only doc by default)
args: <project-slug> [--target <ref>] [milestone|comments]
---
Follow the `project-workflow` skill, and read `{{PW_HOME}}/tooling/rfc.md` (policy) +
`{{PW_HOME}}/tooling/rfc-backends.md` (backend registry) before doing anything — they own the
canonical section schema, the gating rule, and the concrete per-backend invocation. **This command
never hardcodes a platform**; every external call is resolved through those two files.

Arguments: {{ARGS}} — first token = project slug; optional `--target <ref>` sets/overrides the
external doc ref for this and future runs; trailing `milestone` = Wave 2; trailing `comments` =
read-only comment pull. With neither trailing keyword, this is Wave 1 (default).

Project dir: `{{PW_PROJECTS}}/<slug>`. **This is a side-loop, not a phase** — it never sets the
dashboard `Status:` (only `pw-lib.sh log`, for the audit trail), and it only ever externalizes an
artifact **already approved** through the pipeline's own gates. Never block a phase or refuse to
run because a backend is unset/unreachable — that's a config choice, not an error.

## Resolve the backend + target (every invocation — read-only computation, no gate check yet)
This step only **computes** values and, if you explicitly gave `--target`, **records** it — it
never decides to publish anything and never asks you a question. **Whether a wave actually
proceeds is decided entirely by that wave's own gate below**, checked first and cheaply, before any
of this matters — so an unapproved project always just refuses, and is never bothered with a
target question it doesn't need yet.
1. **Backend** = `PW_RFC_BACKEND` from `pw.config.sh` (default `markdown` if unset — the
   zero-dependency default, see `rfc.md`).
2. **Target ref**, in this order: this run's `--target` flag → `rfc/META.md`'s persisted `Target:`
   (if the project already has one) → the backend's own configured default, if any (per
   `rfc-backends.md`) → none. Under `markdown` there is no external target — skip this. If
   `--target` was given, persist it now: `{{PW_HOME}}/tooling/pw-lib.sh rfc target <slug> <ref>`
   (this only records where a *future* publish would go — it's bookkeeping, not RFC content, so
   it's fine to record even if this invocation's gate ends up refusing below).
3. `rfc init` (creating the local doc + metadata) happens **inside each wave below, after its gate
   passes** — never before. RFC publishing only ever externalizes work already approved; creating
   even a local placeholder ahead of that would contradict it.
4. **The "no target resolved" stop-and-ask** (below) is checked **inside each wave, immediately
   before its actual publish sub-step** — not here. Asking about a destination is only warranted
   once a wave's gate has passed and there's real generated content ready to show you; asking
   before that would mean bothering you about *where* to publish something that might never even
   be approved to publish at all.

## Wave 1 (default — no trailing keyword)
1. **Gate:** read `{{PW_HOME}}/tooling/pw-lib.sh phase <slug>` and the analysis review file's
   Sign-off row. If analysis isn't `approved ✅`, **refuse and report why** — do nothing else, and
   do not create `rfc/RFC.md`.
2. Gate passed: `{{PW_HOME}}/tooling/pw-lib.sh rfc init <slug> <backend>` — idempotent; creates
   `rfc/RFC.md` from the template and stamps `rfc/META.md`'s `Backend:` with the **real** resolved
   backend from step 1 above (not a default guess), no-ops (and never clobbers) on a later run.
3. Fill Background, Requirements + Out of Scope, Solution (Approach #1/#2), Dependencies from the
   approved `analysis/<topic>.md`, per the canonical section schema in `rfc.md`. Fill Rollout
   Plan / Rollback Plan **only if I explicitly ask** in this invocation — leave them as template
   placeholders otherwise. **If the external template pre-populates a section you have no
   generated content for** (e.g. its own "Approach #2" placeholder when analysis found no
   alternative) — **leave that section's existing content untouched**; do not delete or edit it
   unless I explicitly ask you to.
4. **Diagrams** (Block/Sequence Diagram subsections): **auto-generate by default** for each
   Approach actually written up — generate mermaid from the relevant analysis section and render
   it via an **isolated sub-agent call** (per `rfc.md`'s diagram rule — never a persistent agent).
   Skip this step only if I explicitly say not to. **On any rendering failure, leave a plain-text
   placeholder noting manual follow-up and continue** — a diagram must never block the rest of the
   publish; the failure path is what's conditional here, not the attempt itself.
5. Write the result into `rfc/RFC.md`, touching only the sections this wave owns (never Glossary
   or References). **Show me the local diff and confirm before touching anything external.**
6. If backend ≠ `markdown` and I confirm: **first**, if no target resolved in the preamble (this is
   the project's first publish to this backend and none of the three sources gave a ref) — **stop
   here and ask me** where to create the doc (a folder/space token, or to set a backend default in
   `pw.config.sh`) **before making any external call**. Never silently pick a location (e.g. Drive
   root) — this is the right moment to ask, now that you've already seen real generated content is
   ready. Otherwise (a target did resolve): publish section-by-section via that backend's
   `create_from_template` / `fetch_anchors` / `update_section` (per `rfc-backends.md`) — **never a
   whole-doc overwrite**, ever. First publish on a project with no doc yet: `create_from_template`
   **at the resolved target** (never a location I wasn't asked about), capture the resulting ref,
   persist it (`pw-lib.sh rfc target`). Otherwise: `update_section` per changed section only.
7. Record: `pw-lib.sh rfc state <slug> Wave1Published yes`,
   `pw-lib.sh rfc dashboard <slug> "<one-line status + link if published>"`,
   `pw-lib.sh log <slug> rfc "Wave 1 published (<backend>)"`.
8. **Recap:** which sections were filled, whether/where it published, and any diagram that degraded
   to a placeholder.

## `milestone` (Wave 2)
1. **Gate:** if `task/PLAN.md` isn't `approved ✅` (its review file's Sign-off row), **refuse and
   report why** — do nothing else.
2. Gate passed: `{{PW_HOME}}/tooling/pw-lib.sh rfc init <slug> <backend>` if `rfc/RFC.md` doesn't
   exist yet (idempotent — normally a no-op here since Wave 1 already ran, but covers the case
   where `milestone` is run without ever running Wave 1).
3. Fill **Milestone** from `task/PLAN.md`'s dependency-DAG groups + task table + the manual-
   execution SP/timeline estimate (one `### Milestone #n` per DAG group is a reasonable default —
   use judgment if the PLAN's own structure suggests a different split) and **Conclusion**.
4. Same diff-confirm-publish-record-recap steps as Wave 1 (steps 5–8 above), setting
   `Wave2Published` instead of `Wave1Published`.

## `comments` (read-only pull — never writes to the external platform)
1. Under `markdown`: **no-op** — report clearly that there's nothing external to read.
2. Otherwise: call the backend's `list_comments` (per `rfc-backends.md`) for **every** thread on
   the doc, including each thread's **resolved state** (e.g. Lark's `is_solved`) and **current
   reply count** — both matter, not just the comment text. Per-thread tracked state (never a
   single "latest" pointer — that can't tell "an earlier thread changed" from "already handled")
   lives in `rfc/META.md`'s "Comment tracking" table; read it to know what you've already recorded
   for each thread (reply count + solved, keyed by thread ID).
3. For each thread, compare its live state to what's tracked (or "not tracked" if this is the
   first time you've ever seen this thread ID):
   - **Resolved on the platform, not tracked yet** — skip entirely; it was resolved before you
     ever looked, nothing to surface.
   - **Resolved on the platform, tracked as previously unresolved** — append a short note to its
     **existing** item in `analysis/review/RFC.review.md` ("🔄 resolved externally on `<backend>`
     — no action needed unless you want it reflected in the analysis too"). Do **not** flip the
     item's own 🔴/🟢 dot — that stays owned exclusively by `/pw-review`; this is informational.
   - **Resolved on the platform, already tracked as resolved** — nothing to do, already noted.
   - **Unresolved, not tracked yet** — a genuinely new thread: create
     `analysis/review/RFC.review.md` if it doesn't exist yet
     (`{{PW_HOME}}/tooling/pw-lib.sh review-init <slug> analysis/review/RFC.review.md
     analysis/<topic>.md`), then append a **new** item — quote the comment, name the author, link
     the thread, note the canonical section it's anchored to.
   - **Unresolved, tracked, and its current reply count is HIGHER than what's recorded** — new
     discussion since your last pull. **Do not create a duplicate item and do not touch the
     human's own existing text.** Append only the *new* replies (the ones beyond the tracked
     count) underneath that **same** existing item, as a running transcript — same convention as
     local `.review.md` files never being rewritten, only appended to.
   - **Unresolved, tracked, reply count unchanged** — nothing to do, already surfaced.
4. **Never reply to, resolve, or otherwise write into the external thread — that's mine to do.**
   After handling each thread, record its current state:
   `pw-lib.sh rfc comment-seen <slug> <thread-id> <reply-count> <solved:yes|no>`.
5. **Recap:** how many genuinely new items were pulled, how many existing items got new replies
   appended, how many were noted as resolved externally, and remind me to run `/pw-review` to
   apply any of this to the analysis locally (its `↳ agent:` reply is the durable record of what
   changed), then re-run `/pw-rfc <slug>` (or `milestone`) to push the revision.

## What this command never does
- Never sets the dashboard `Status:` or advances/rewinds a phase.
- Never creates `rfc/RFC.md` before its wave's gate has passed.
- Never guesses a target location for a first publish — asks instead of picking one.
- Never deletes or edits an external template's pre-populated section that has no corresponding
  generated content — leaves it untouched unless explicitly asked.
- Never replies to, resolves, or otherwise writes into an external comment thread.
- Never performs a whole-doc overwrite on any backend — every external write is section-scoped.
- Never blocks a phase because a backend is unset or unreachable — RFC publishing is best-effort
  enrichment on an already-complete artifact; report and continue.
