# analysis/ — the "what & why"

Agent-produced analysis of the context. One doc per topic (`<topic>.md`), from
[`_TEMPLATE.md`](./_TEMPLATE.md).

Analysis **describes and reasons** — it does not yet cut work into tasks. It answers:

- What needs to change, and **why**?
- Which repos/services/files are affected?
- What are the risks, unknowns, and open questions?
- What options exist, and which is recommended?

This is the cheapest place to catch a misunderstanding, so iterate here with the human until
approved **before** any task breakdown. Files starting with `_` are templates, not analyses.

**Review:** feedback lives in `review/<topic>.review.md` (a `review/` subdir here, from
`../_REVIEW.template.md`), not inline — the agent rewrites this doc when applying fixes. The agent
reads the review file first, replies with `↳ agent:` and flips `[OPEN]`→`[RESOLVED]`, and never edits your comment
text. Only you sign off. See `../README.md` → "Review & feedback".
