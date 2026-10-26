# Security reference — the ten-minute checklist for a change

Canonical doctrine: [`tooling/docs/SECURITY.md`](../../../docs/SECURITY.md) — threat model, boundary
table, accepted residuals. Load it whenever a change touches input handling or file writes.
This reference is the prompt: run it before every bundle change that adds or moves a surface.

## Checklist — "am I about to open a hole?"

1. **New flag / operator / parser?** Where does the VALUE go — a path, a git command, a program
   string, a variable name, arithmetic, a table cell?
   - path → `pw_proj_slug_ok` / `pw_task_id_ok` / `pw_dir_within` at the consumer
   - git command → `pw_branch_ok` before any positional refspec; never a dash-leading value
   - program string → NEVER; bash replacement or `awk -v`
   - variable name → charset gate at the sink (`model-check`, `pw_api_entries` pattern)
   - arithmetic → `*[!0-9]*` refusal before `$(( ))`
   - table cell / row → reserved-char gate (`|`, TAB, newline, backslash)
2. **New file write?** Stage via `pw_tmpfile` + `mv`. No fixed-name `.tmp` suffixes — the static
   table bans them. Cleanup paths (`rm -f`) reuse the same variable.
3. **New read of a project file?** Through a physically-resolved, contained path; symlinked
   review files are never followed (lane policy). Grades: refuse (`[ -L ] && die/skip`).
4. **New subprocess with data in argv?** Quote; prefer `--flag value` positions (pflag consumes
   dash-leading values); never `sh -c` on task-file content; prefer stdin for prompt text.
5. **New URL/host from a document?** Cross-check against the repo `origin` (see `monitor`,
   `_stack_mr_view`); never let document content pick the destination of a credential call.
6. **Did you add it to the enforcement floor?** a `pw-security.t.sh` check (refusal or inert
   behavior), the matching static idiom if a banned shape applies, and a mutation row that
   fails when the gate is reverted. The register lives in
   `tooling/tests/expectations/mutations.tsv` (next free C-number).

## Quick map of the guards

| Guard | Lives in | Kills |
|---|---|---|
| `pw_proj_slug_ok` / `pw_proj_dir` | pw-common | traversal slugs, symlink outward |
| `pw_task_id_ok` | pw-common | `T1/../x`, globs, ERE shapes in ids |
| `pw_branch_ok` | pw-common | `--force`/`--all` argument injection |
| `pw_dir_within` | pw-common | repo/worktree traversal, symlinked dirs |
| `pw_hook_dir_ok` | pw-common | empty/relative hook install dirs |
| `pw_stamp_tokens` | pw-common | install paths as perl/sed program text |
| `_stack_val_bad` | pw-common | reserved chars in state rows |
| `pw_tmpfile` | pw-common | planted-symlink staging clobbers |
| reserved-char gates | mdlib writers, pw-config, pw-ship, pw-doc | table/row forgery via `awk -v` escapes |
| marker gate (`pw-generated`) | gen-commands/gen-agents + pw-doctor | orphan sweeps deleting foreign files |

When in doubt: grep the class in `tooling/tests/cases/pw-security.t.sh` — every guard has a
refusal check there, and `bash tooling/tests/pw_test.sh --mutation C2` proves the pins bite.
