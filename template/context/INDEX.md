# Context index

`context/` holds the raw inputs the agent reasons from — tickets, RFC/PRD excerpts, code refs,
logs, chat threads. **Purpose of this index:** record *what each input is* and *where it came
from*, so later phases (and future-you) know what to trust and can trace a claim back to its
source. Fill one row per input. Prefer links + short excerpts over dumping huge files.

**Filled by:** [🧑 you] — both tables below. Agents only READ what you write here. **Exception:**
on continuation projects, `/pw-adopt` deterministically maintains its own rows — a one-time generic
`ADOPTED.md` provenance row above, and the adopted `(repo, base)` rows in the "Repos in scope" table
(the `<!-- pw-adopt-scope:… -->` marker rows). Don't hand-edit those.
(Legend: 🧑 you fill · 🤖 agents fill/maintain, don't hand-edit · 🤖🧑 both.)

| File / link | What it is | Source (ticket / URL / person) | Date added | Trust notes |
|-------------|-----------|--------------------------------|------------|-------------|
| _e.g._ `spring-boot-3-rfc.md` | Migration RFC excerpt | Lark doc `docs/xxxx` | 2026-08-03 | Approved RFC |
| | | | | |

**Column meanings** (the two that get confused):
- **File / link** — the artifact *sitting in this `context/` dir* (a filename you dropped here,
  e.g. `spring-rfc.md`), or a bare URL if you didn't copy it locally. A bare URL means `/pw-analyze`
  fetches it live (via WebFetch or the matching platform skill) rather than treating the link
  itself as content — so it still ends up as *the copy the agent actually reasons from*.
- **Source** — where that artifact *originally came from*: the JIRA/ticket ID, the Lark/Confluence
  URL, or the person who gave it to you. This is *the origin/provenance*. (File/link = the copy;
  Source = where it came from.)
- **Trust notes** — how authoritative it is, so analysis can weight it: "approved RFC",
  "draft — may change", "Slack thread, unofficial", "my own notes".

## Repos in scope — first guess (analysis confirms/corrects)

Your **best guess** at which repos this work will touch, filled *now* so the analysis phase knows
where to start looking. It is only a starting point — **analysis verifies each repo's real state**
(actual base branch, module shape, real dependency versions on `master`, not a parked feature
branch) and may add, drop, or correct rows. Do not treat this table as final; the analysis doc's
"Affected repos" section is the confirmed version. If a repo needs work on **more than one base
branch** (e.g. `master` and `spring3`), give it **one row per base**.

> **Adopted (continuation) projects:** `/pw-adopt` maintains this table for you — it upserts one
> row per adopted `(repo, base)` deterministically (via `pw-lib.sh adopt`, keyed by a hidden
> `<!-- pw-adopt-scope:… -->` marker). **Don't hand-edit those marker rows** — that's what let a
> later adoption clobber earlier ones. You may still add your own un-marked guess rows above/below.

| Repo (in `{{PW_REPOS}}/`) | Base branch (guess) | Why it's in scope |
|----------------------------|---------------------|-------------------|
| _e.g._ `hera` | `master` | Owns the Kafka producer config the RFC wants toggled |
| | | |
