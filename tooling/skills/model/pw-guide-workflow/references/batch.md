# Batch operations (`/pw-batch`)

Load this reference when the human asks for several supported operations in one request.
It owns normalization, validation, dispatch, and recovery. The supported-operation table lives in
the `pw-batch` human entry; that table is the allowlist.

## 1. Read the request

1. Read the mode. `preview` is the default; `apply` must be explicit or clearly requested.
2. Take the batch project from `--project <project-slug>`. It may be absent for global-only lists.
3. Split the rest into numbered items. Each item is one `/pw-*` command with its own named
   arguments. Items run in the order written.
4. Reject a nested `/pw-batch`, two batch headers, or text outside an item or its literal block.

An item's header is one numbered line. Lines continue the item only when they are indented under it
and belong to a literal block (section 2). A blank line between headers is optional.

Project-scoped forms omit `--project` and inherit the batch project.
If an item repeats `--project`, the slug must match. A different slug, or a project form with no
batch project and no item project, fails structural validation.
Global forms never receive the batch project.
`/pw-help project` needs an explicit `--project` because it selects a project view.
`/pw-status --all` and `/pw-config global …` are global even in a project batch.
A project batch refuses a bare `/pw-doctor` item: name `--project <same-slug>` for the project
check, or run the global install check in a batch without a project.

## 2. Literal payloads

Only `/pw-review item` and `/pw-review answer` accept a literal payload.
The item header ends with `--stdin`. The next lines form one indented fenced block:

````text
1. /pw-review item --file task/review/PLAN.review.md --section "Failure handling" --stdin
   ```text
   Retry ownership:
   1. The executor retries once.
   2. The reviewer confirms the second failure.
   ```
````

Rules:

- The opening fence is at least three backticks, optionally followed by `text`, and indented under
  the item. The closing fence uses the same indent and at least the same backtick count.
- De-indent by the opening fence's indentation. Preserve blank lines and relative indentation.
- Remove only the fence lines. Everything inside is payload, including numbered lines, slashes,
  `--flags`, tables, and HTML.
- Feed the payload to the helper's stdin. Never interpolate it into a shell string.
- Reject a missing block, an unterminated block, more than one block for one item, `--text` on the
  same item as `--stdin`, or `--stdin` on any other form.

`/pw-context add-input`, `add-repo`, and every other item take their documented prose flags and
keep the standalone grammar: a value runs until the next `--flag`.

## 3. Validate before the first operation

Structural validation covers the whole list and happens before any helper runs:

1. Mode is `preview` or `apply`.
2. The command and operator are in the allowlist table, with an accepted scope form.
3. Required selectors and values are present for that form.
4. Project inheritance is consistent; global forms carry no injected project.
5. A literal payload satisfies section 2.
6. The form has no excluded flag or mode: `--fix`, `stack adopt`, ship `comments`/`--resolve`,
   `models`, `agent-model*`, `spawn-args`, `global --key agent-model`,
   status `update` or `rewind`, `auto-signoff`, `materialize`, `model-resolve`, `prepare`, `import`,
   `ai`, or an apply-comments flow. A `/pw-ship ready|draft` item may carry `--apply` only with its
   own `--expect <token>` or `--resume <attempt-id>`; every other item-level `--apply` is refused.
7. Duplicate non-repeatable selectors and conflicting duplicate config members are refused.
   Deliberate repeated items are not deduplicated.
8. An item that targets a review file created by an earlier `init` item is allowed. Do not require
   a future file to exist yet.

Semantic validation stays with the owning helper at execution time: enum values, model capability,
document metadata, question state, review gates, and task evidence.
Do not duplicate those rules here, and do not run a mutating helper as a speculative check.
Preview reports state-dependent checks as deferred when it cannot prove them without execution.

**Shipment and readiness dependencies.** A shipment item runs with the owning ship gates and a
concrete publication confirmation; the generic batch `apply` never authorizes a publication list.
A later readiness item may target an MR created earlier in the same batch, but it must not invent
an expectation token for it. Use a readiness preview after the shipment, then a separately
authorized apply with that token. Batch preview never publishes, opens an MR, or writes a readiness
journal. A batch applies serially; a failed or uncertain item stops later items, and successful
shipments are neither replayed nor rolled back.

## 4. Dispatch map

Use the owning command's mapping. These are the concrete helpers behind the allowlist:

| Item form | Helper invocation |
|---|---|
| `/pw-context req-init` | `pw-context.sh req-init --project <slug>` |
| `/pw-context add-input` | `pw-context.sh add-input --project <slug> --file <f> --what <w> --source <s> [--trust <t>]` |
| `/pw-context add-repo` | `pw-context.sh add-repo --project <slug> --repo <r> --base <b> --why <w>` |
| `/pw-review init` | `pw-review.sh init-docs --project <slug> --file <artifact>…` |
| `/pw-review init-all` | `pw-review.sh init-all --project <slug>` |
| `/pw-review item` | `pw-review.sh add-item --project <slug> --file <review> --section <anchor> (--text <ask> \| --stdin)` |
| `/pw-review answer` | `pw-review.sh answer --project <slug> --file <review> --question <Qid> (--text <answer> \| --stdin)` |
| `/pw-review signoff` | `pw-review.sh signoff --project <slug> --file <review> --decision <decision> [--by <name>]` |
| `/pw-config show` | `pw-config.sh show --project <slug> [--json]` |
| `/pw-config get` | `pw-config.sh get --project <slug> --key <key> [--json]` |
| `/pw-config set` | `pw-config.sh set --project <slug> --key <key> [--value <v> \| --set <member=value>]…` |
| `/pw-config ensure` | `pw-config.sh ensure --project <slug>` |
| `/pw-config model-check` | `pw-config.sh model-check --provider <p> --model <m> [--variant <v>] [--reasoning <v>] [--effort <v>] [--json]` |
| `/pw-config global show`, `get`, `set`, `unset` | `pw-config.sh global (show/get/set/unset) …` — `show [--json]`, `get --key <key>`, `set --key <key> …`, `unset --key <key>`; `--key agent-model` and `--provider/--agent` are NOT admitted |
| `/pw-status` | `pw-status.sh --project <slug> [--skip-cli-check]` |
| `/pw-status --all` | `pw-status.sh --all [--attention] [--phase <phase>] [--json]` |
| `/pw-help …` | `pw-help.sh <form> …` exactly as the standalone form |
| `/pw-doctor` (global) | `pw-doctor.sh` |
| `/pw-doctor --project` | `pw-doctor.sh --project <slug> [--guidance]` |
| `/pw-ship stack` | `pw-ship.sh stack --project <slug>` |
| `/pw-ship` | the human `pw-ship` entry's full ship procedure (never a direct `exec` shortcut) |
| `/pw-ship ready` | `pw-ship.sh ready --project <slug> --task <T0n>… [--apply --expect <token> \| --apply --resume <id>]` |
| `/pw-ship draft` | `pw-ship.sh draft --project <slug> --task <T0n>… [--apply --expect <token> \| --apply --resume <id>]` |

Run each helper exactly once for its item. Do not add flags the human did not supply.
Do not convert a read-only item into a repair. Do not run any helper the table does not name.

## 5. Preview

Print the normalized plan and stop:

```text
/pw-batch preview --project demo
  1. pw-context add-repo — project demo — storefront @ main            write
  2. pw-review init-all — project demo — analysis/review/*.review.md   write
  3. pw-config set — project demo — review-rounds=2                     write
  4. pw-help overview — global                                          read (apply only)
```

Preview may read the dashboard phase to expand `init-all` and may check whether a named `init`
artifact exists. It must not run the status report, help, doctor, model-check, stack preview,
workers, forge calls, or model requests. It writes no file, log line, review row, or config value.
Mark deferred semantic checks as deferred.

## 6. Apply

1. Record the dashboard phase with `pw-status.sh phase --project <slug>` when the list is project
   scoped. Before an `init-all` item, read it again. If the phase changed, stop and report drift.
2. Run each item in order. For a project item, append `--project <slug>` unless the item already
   carried it. For a global item, never append it.
3. Capture stdout and stderr for the evidence line. Paste required help/doctor/report output in its
   own labeled block; do not reduce a required report to a one-line summary.
4. Read back the affected record or key. For review and context writes, confirm the new row exists.
   For configuration, read the value back with the documented read form.
5. On a nonzero exit, stop. For a read-only item, report the diagnostic findings as `blocked` and
   leave later items unattempted. For a write, decide `failed` when the helper refused before the
   write, or `uncertain` when a write may have landed without a provable result.

Existing helpers keep their own logging, idempotence, validation, and attribution.
`init` and `ensure` are idempotent. Append operations are not assumed idempotent.

## 7. Report

Use one table or one line per item:

```text
/pw-batch apply --project demo — 3 succeeded, 1 failed, 0 unattempted
  1. pw-context add-input — succeeded — context/INDEX.md row added
  2. pw-review item — succeeded — task/review/PLAN.review.md R4
  3. pw-review signoff — failed — open items remain in task/review/PLAN.review.md
  4. pw-config set — unattempted
```

Name the affected file or global key and the evidence. State that completed writes remain.
Give the next safe action for the stopped item in `/pw-*` terms. Do not claim rollback.

## 8. Recovery

Never replay the whole list after an interruption. Inspect the affected review content, context
rows, configuration value, or log, then resume with the remaining operations.
A missing response does not prove a write failed.
If a prior append cannot be attributed safely, report `uncertain` and ask for the human's decision
instead of appending a duplicate.
`init-all` drift and a changed target set stop the list; re-preview before continuing.

## 9. Prohibitions

- No arbitrary shell, script path, semicolon chain, pipeline, or command substitution.
- No parallel writes, continue-on-error, automatic rollback, or fabricated transaction.
- No cross-project writes, nested batches, or implicit project injection on global forms.
- No inferred signoff, task acceptance, execution, phase move, or publication.
- No implicit doctor fix, document sync, configuration ensure, reopen, import, or repair.
- No new script: this entry coordinates the owning helpers.
