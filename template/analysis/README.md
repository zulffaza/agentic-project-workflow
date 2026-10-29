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

Persisted exploration and research artifacts live under `research/`:
`<topic>.exploration.md` (bounded orientation map), `<topic>.ground-truth.md` (source-grounded
pack), `<topic>.seed.md` (handoff seed), and `<topic>.answer.md` (scoped answer). Resolve the
path with the docs entity's `research-path` operator for the project, topic, and kind; it creates
nothing. Older `_research/` paths remain readable.

**Review:** feedback lives in `review/<topic>.review.md` (a `review/` subdir here, from
`../_REVIEW.template.md`), not inline — the agent rewrites this doc when applying fixes. The agent
reads the review file first, replies with `↳ agent:` and flips `[OPEN]`→`[RESOLVED]`, and never edits your comment
text. Only you approve (guarded AI `auto` mode aside). See `../README.md` → "Review & feedback".

**Common actions**

| You want to… | Use |
|---|---|
| Start a review for this doc | `/pw-review init --project {{PW_PROJECT_SLUG}} --file analysis/<topic>.md` |
| Add feedback | `/pw-review item --project {{PW_PROJECT_SLUG}} --file analysis/review/<topic>.review.md --section §<section> --text <your comment>` |
| Answer the agent's questions | `/pw-review answer --project {{PW_PROJECT_SLUG}} --file analysis/review/<topic>.review.md --question Q<n> --text <your answer>` |
| Have the agent apply approved fixes | `/pw-review --project {{PW_PROJECT_SLUG}} --file analysis/review/<topic>.review.md` |
| Ask for an independent AI pass | `/pw-review ai --project {{PW_PROJECT_SLUG}} --surface analysis` |
| Approve (human-only) | `/pw-review signoff --project {{PW_PROJECT_SLUG}} --file analysis/review/<topic>.review.md --decision approved` |
