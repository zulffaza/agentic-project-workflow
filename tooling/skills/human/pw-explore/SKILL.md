---
name: pw-explore
description: Map where relevant code and documents live inside a bounded budget — candidate files, entrypoints, dependencies, and test surfaces, with coverage gaps. Read-only orientation; use /pw-research for evidence-grounded answers.
args: "(--repo <path> | --project <project-slug>) --question <prose…> [--topic <topic>] [--area <path>] [--query <term>]… [--changed <base>] [--mode brief|standard|deep] [--out <path>] [--inline-lanes]"
scope: mixed
scope-forms: "--repo=global, --project=project, --out=global"
args-global: "--repo <path> --question <prose…> [--topic <topic>] [--area <path>] [--query <term>]… [--changed <base>] [--mode brief|standard|deep] [--out <path>] [--inline-lanes]"
args-project: "--project <project-slug> --question <prose…> [--topic <topic>] [--area <path>] [--query <term>]… [--changed <base>] [--mode brief|standard|deep] [--out <path>] [--inline-lanes]"
---

**Load shared guidance first.** Read the `pw-orchestration` skill's common rules
(`references/common.md`) before acting: authorization, operation scope, helper ownership, and
reporting. Load only the phase-specific references this operation needs. A producing operation
may spawn the canonical `pw-explorer` worker; it never edits source.

Arguments: {{ARGS}} — exactly one of `--repo <path>` or `--project <project-slug>`.

**This is orientation, not research.** Use `/pw-explore` to find the candidate files, entrypoints,
dependencies, and tests that matter. Use `/pw-research` when an answer needs evidence, confidence,
or source grounding. Do not let a map replace verification, a fresh review, or a gate decision.

1. Parse the selector and prose flags. `--question` and `--topic` run until the next `--flag`.
   `--query`, `--area`, and `--changed` are repeatable/named scalars. Omitted `--mode` means
   `standard`.
2. If a bounded scan exists in the brief, reuse it. Otherwise run one scan:
   `{{PW_HOME}}/tooling/scripts/entities/pw-context.sh scan --repo <path> [--area <path>] [--query <term>]… [--changed <base>]`.
   The scan is read-only and bounded; report its truncation/coverage lines, never hide them.
3. Spawn or run the canonical `pw-explorer` worker with the scan, question, mode, and output
   policy. Same-provider native spawn is preferred when it can honor the model binding; otherwise
   use the authorized headless route. Inline is allowed only when no strict pin is lost; record
   the fallback reason.
4. Answer inline by default for a bare repository request. Persist only when `--out <path>` is
   given (or a project brief explicitly asks for an artifact). For a project artifact, resolve
   the canonical path with
   `{{PW_HOME}}/tooling/scripts/entities/pw-doc.sh research-path --project <slug> --topic <topic> --kind exploration`,
   then create the parent and refuse an unintended overwrite.
5. Report the map, the inspected-vs-candidate split, coverage gaps, and the identity/route line.
   A map that found nothing in an unsearched area must say the area was not searched.

**Optional prepass.** Use explorer where uncertainty justifies it: assisted context, adoption,
analysis, RFC preparation, breakdown, execution orientation, large review targets, and ship/sync
dependency mapping. Never insert an obligatory extra model call into every phase. The cross-MR
`pw-ship-comment-analyst` already performs its own bounded exploration; do not launch an explorer
before it or replace its evidence with an orientation map.
