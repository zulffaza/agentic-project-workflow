<!--
  OPTIONAL one-page brief. Use it to hand the agent a crisp statement of *what you want and why*
  before it reads the raw context. To use: copy this file to REQUIREMENTS.md in this dir, fill it,
  and add a row for it in INDEX.md. Skip it entirely if the tickets/docs in context/ already say
  enough — the pipeline never requires this file.

      cp _REQUIREMENTS.template.md REQUIREMENTS.md

  Keep it short (this whole doc should fit on one screen). It's a brief, not a spec — the analysis
  phase turns it into the detailed "what & why". Delete these comments when you fill it.
-->
# Requirements — <project-slug>

**One-liner:** <the change in a single sentence — what will be different when this is done>

## Problem / motivation
<Why are we doing this? What's broken, missing, or risky today? 2–4 sentences.>

## Goal — done looks like
<The outcome you want, stated as an observable end state. Not the how — the what.>
- <e.g. "all in-scope services build against Spring Boot 3.x on their base branch">
- <e.g. "the feature toggle X is removed and its two code paths collapsed to one">

## In scope
- <what this project WILL change>

## Out of scope (explicitly not now)
- <what to deliberately leave alone — prevents scope creep during analysis/breakdown>

## Constraints & non-negotiables
- <deadlines, must-not-break behaviours, compatibility requirements, approvals needed>
- <pinned versions / libraries that must stay as-is, and why>

## Success criteria (how we'll verify)
- <the check that proves it worked — ideally something runnable, e.g. "mvn verify green on all
  in-scope repos", "toggle absent from config + integration test T passes">

## Known context & links
- <ticket / RFC / PRD / Slack thread — each also gets a provenance row in INDEX.md>

## Open questions (optional)
- <anything you already know is unresolved — analysis will pick these up>
