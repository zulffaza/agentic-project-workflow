# Learn + close (`/pw-close`)

After a run, `/pw-close`: verify all tasks `accepted`, **tear down worktrees with the safe helper**
(`tooling/pw-teardown.sh <project-dir>` — it won't remove the worktree you're standing in or a
dirty one, the guard that stops an editor closing on you; don't delete branches/project dir), seed
workflow-level learnings **if a memory tool is configured** (`PW_MEMORY`; mark superseded facts
`[SUPERSEDED]`), improve the bundle's `template/` files or this skill, set `Status: done`, and
summarize MRs/leftovers. Don't save what the repos/commits already record. **`accepted` ≠ merged**
— a project closes on verified + MR opened + human sign-off; open/on-hold MRs don't block close-out
(record their state in the dashboard). Don't delete branches or the project dir.

**If `REVIEWER-NOTES.md` exists**, fold its accumulated `**Lessons:**` bullets into the same
memory-seeding step above (dedupe against what's already there, mark superseded — same discipline,
one more source, not a second seeding pathway). `REVIEWER-NOTES.md` itself is never deleted at
close — it's the project's own always-available record regardless of whether memory is configured.
