# Known issues & verified gotchas

← [back to README](../README.md)

This is the index of hard-won, empirically-verified operational knowledge baked into this bundle
— the kind of thing you'd otherwise only discover by hitting it yourself. Each entry: the symptom,
the root cause, the mitigation already built in, and a date. Full technical detail (exact
commands, raw API fields, reproduction context) lives at the source link in each entry — this page
is the discoverable summary, not a second copy of the truth.

**Why this exists as its own page:** this knowledge used to be reachable only by reading
`tooling/docs/providers.md`/`forges.md` end to end. It's the single best answer to "why trust this
bundle over rolling your own" — so it gets a page under `docs/` where you'd actually look, not
buried in `tooling/`.

## Cross-provider execution (an orchestrator on one Agent Provider invoking another headlessly)

### A long inline prompt argument can silently vanish across a shell-out boundary
- **Symptom:** `claude --print` reports `Error: Input must be provided either through stdin or as
  a prompt argument when using --print` — even though the prompt was right there in the command,
  and the CLI's own flags/quoting are fine in isolation.
- **Root cause:** something inside the calling tool's own command construction drops a long inline
  argument during a shell-out; confirmed on two separate cross-provider pairings (kilo→claude and
  KiloCode→claude, both dates below).
- **Mitigation (built in):** every headless invocation in this bundle pipes the prompt via stdin
  (`printf '%s' "$PROMPT" | claude ...`) instead of a trailing argument — stdin is immune. Applies
  defensively to any cross-provider handoff, not just this pairing.
- Verified 2026-08-08 (twice, both directions). Full detail:
  [`tooling/docs/providers.md`](../tooling/docs/providers.md#verification-notes-historical).

### `kilo run` auto-rejects every permission without `--auto`
- **Symptom:** a headlessly-invoked `kilo run` executor can't even read its own task file.
- **Root cause:** `kilo run` defaults to rejecting all permissions when there's no interactive
  session to approve them — the opposite of what you'd want for automation.
- **Mitigation (built in):** `--auto` is treated as mandatory in every kilo headless invocation
  this bundle generates (`kilo_headless()` in `tooling/pw-common.sh`).
- Verified end-to-end 2026-08-04. Same spirit for claude: `--dangerously-skip-permissions` is
  mandatory headless too — without it, a permission prompt has no TTY to answer and the process
  hangs producing zero output. Full detail:
  [`tooling/docs/providers.md`](../tooling/docs/providers.md#verification-notes-historical).

### "KiloCode auto-approve breaks inside git worktrees" is a JetBrains-plugin issue, not the CLI
- **Symptom:** a documented gotcha claims worktrees break KiloCode's auto-approve (plausible,
  since a worktree's `.git` is a *file* pointer, not a directory, and some config loaders don't
  detect that as a git boundary).
- **Verified reality:** the **CLI** is unaffected — a headless `kilo run` executor created a
  worktree, wrote files, and committed inside it without issue. The breakage is specific to the
  KiloCode **JetBrains plugin's** auto-approve, a different surface entirely.
- Verified 2026-08-04. Full detail:
  [`tooling/docs/providers.md`](../tooling/docs/providers.md#verification-notes-historical).

## GitLab MR comment handling

### A field named `individual_note` does not mean "not part of a thread"
- **Symptom:** a real, `resolvable: true`, unresolved reviewer follow-up — posted as a general
  comment (no diff line), `individual_note: false` — was completely missed by fetch logic that
  filtered on `individual_note` or on whether the note had a diff `position`.
- **Root cause:** `individual_note` means "single comment" vs. "threaded reply chain" — a
  *different axis* from diff-anchored-vs-general. A general "Start a thread" comment can be
  `resolvable: true` and `individual_note: false` simultaneously; filtering on either field as an
  actionability signal silently drops real, open feedback.
- **Mitigation (built in):** classify strictly by `notes[].system` (drop only these — real
  activity-log noise), `notes[].resolvable`, and `notes[].resolved` — never by `individual_note`
  or diff-position.
- Corrected 2026-08-10, verified against real production MR data. Full detail:
  [`tooling/docs/forges.md`](../tooling/docs/forges.md#standalone-vs-diff-anchored-comments-both-forges--read-before-writing-a-fetch-comments-step).

### GitLab's `/discussions` endpoint can lag the raw notes table by 20+ minutes
- **Symptom:** a brand-new, completely ordinary diff comment — visible immediately in the GitLab
  web UI — was still missing from the `/discussions` API response over 20 minutes after being
  posted, on a self-hosted instance.
- **Root cause:** `/discussions` groups the raw notes table into threads server-side; that grouping
  projection can lag the underlying data by more than a short retry would cover.
- **Mitigation (built in):** cross-check freshness against the flat `notes?sort=desc&order_by=
  updated_at` list. If its newest non-system note isn't in the `/discussions` pull, don't report
  "nothing open" — retry once or twice, then fall back to a plain new top-level note (no
  `discussion_id` needed) and flag the lag explicitly for a human to verify once the real
  discussion syncs.
- Verified 2026-08-10, self-hosted GitLab. Full detail:
  [`tooling/docs/forges.md`](../tooling/docs/forges.md#discussions-can-lag-the-raw-notes-table--a-freshness-canary-is-required).

## KiloCode API Provider naming

### A credential's display name and its actual usable id can differ
- **Symptom:** the intuitive id for KiloCode's own built-in gateway — `kilo_gateway`, matching the
  `kilo auth list` display name "Kilo Gateway" — errors with `Provider not found`.
- **Root cause:** `kilo auth list` shows a human-readable display name; `kilo models`/`Execute
  with:` resolve against a separate internal id, and the two aren't guaranteed to match. The
  working id for this specific credential is just `kilo`.
- **Mitigation (built in):** `pw.config.example.sh` states the rule directly — always confirm a
  new API Provider id with `kilo models <id>` before trusting it, never infer one from the display
  name alone. `/pw-doctor`'s "Model availability" section does this check for any allowlist
  pattern you configure.
- Verified 2026-08-11 against a real installed `kilo` CLI.

## Template/tooling gotchas (this bundle's own code)

### A review template's own format-hint text can permanently false-positive a naive "is anything open" check
- **Symptom:** a plain `grep -q '🔴 open'` on any review file is *always* true, forever — even one
  with zero real open items.
- **Root cause:** `template/_REVIEW.template.md`'s permanent format-hint blockquote and its
  deletable worked-example block both contain the literal string `🔴 open` as a syntax
  demonstration, by design — a naive whole-file grep can't tell that apart from a real item.
- **Mitigation (built in):** `_review_has_open_marker()` (`tooling/pw-lib.sh`) strips HTML
  comments first, then anchors only to real `### ` headings (not `> ` blockquote lines) — this is
  what the auto-signoff gate actually checks, and it's covered by `pw-lib.sh selftest`.
- Discovered during the AI-review feature's own testing, 2026-08-10.
