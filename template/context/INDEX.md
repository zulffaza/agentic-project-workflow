# Context index

`context/` holds the raw inputs the agent reasons from — tickets, RFC/PRD excerpts, code refs,
logs, chat threads. **Purpose of this index:** record *what each input is* and *where it came
from*, so later phases (and future-you) know what to trust and can trace a claim back to its
source. Fill one row per input. Prefer links + short excerpts over dumping huge files.

**Filled by:** [🧑 you] — both tables below. Agents only READ this; they never populate it.
(Legend: 🧑 you fill · 🤖 agents fill/maintain, don't hand-edit · 🤖🧑 both.)

| File / link | What it is | Source (ticket / URL / person) | Date added | Trust notes |
|-------------|-----------|--------------------------------|------------|-------------|
| _e.g._ `spring-boot-3-rfc.md` | Migration RFC excerpt | Lark doc `docs/xxxx` | 2026-08-03 | Approved RFC |
| | | | | |

**Column meanings** (the two that get confused):
- **File / link** — the artifact *sitting in this `context/` dir* (a filename you dropped here,
  e.g. `spring-rfc.md`), or a bare URL if you didn't copy it locally. This is *the copy you're
  feeding the agent*.
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
"Affected repos" section is the confirmed version.

| Repo (in `IdeaProjects/`) | Base branch (guess) | Why it's in scope |
|---------------------------|---------------------|-------------------|
| | | |
