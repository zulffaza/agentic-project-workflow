# RFC backend registry (publish routing)

**Filled by:** [🤖 maintainer] — the day-to-day settings you actually set are `PW_RFC_BACKEND` /
`PW_RFC_LARK_*` / `PW_RFC_NOTES` in `pw.config.sh`. This file itself is a maintainer-owned
implementation spec — a registry `/pw-rfc` reads at publish time — not something you edit
day-to-day; adding a genuinely new backend (Confluence/Notion/etc.) is a real integration project
(OAuth flow, API contract, platform-specific limitations), not a quick config edit.

`/pw-rfc` always **generates** `<project>/rfc/RFC.md` locally first, regardless of backend (see
[`rfc.md`](./rfc.md)'s Generate/Publish split). **Publishing** that to an external doc is optional
and backend-specific. Every backend implements the same 4-operation contract so `/pw-rfc`'s command
logic never special-cases a platform:

| Operation | Purpose |
|---|---|
| `create_from_template` | Instantiate a new RFC doc from that platform's template/blueprint |
| `fetch_anchors` | Map the canonical section schema (`rfc.md`) → that platform's real anchors |
| `update_section` | Push one section's content, **scoped to that section's anchor** — never a whole-doc overwrite (this is what keeps a reviewer's anchored comment from being orphaned) |
| `list_comments` | Read-only pull of **every** comment thread, each with its **resolved state** (the platform's own flag, e.g. Lark's `is_solved`) and **current reply count** — both are required, not just the comment text, since `/pw-rfc comments` uses them (via `rfc/META.md`'s per-thread tracking) to tell a new thread from an updated one from an already-resolved one. Never filter to "open only" server-side if that means losing the resolved ones silently — an already-tracked thread that just became resolved still needs one informational note locally. |

Backend selection: `PW_RFC_BACKEND` in `pw.config.sh`, or a resolution order of `--target` flag →
project `rfc/META.md` → config default (see `rfc.md`).

## Registry

| Backend | Status | `create_from_template` | `fetch_anchors` | `update_section` | `list_comments` | Auth / notes |
|---|---|---|---|---|---|---|
| `markdown` | **Implemented — bundle default** | n/a — operates purely on local `rfc/RFC.md`, no external doc exists | n/a | direct edit of `rfc/RFC.md` (still section-scoped — an agent editing it should touch only the section in play, so a human's inline note elsewhere in the file survives) | n/a — no-op with a clear message (nothing external to read) | None. Zero external calls, zero dependency — this is what keeps onboarding trivial. |
| `lark` | **Implemented** | `lark-cli drive files copy` of the template token in `PW_RFC_LARK_TEMPLATE`, into the space/node resolved per the target-resolution order above. **Requires a resolved target — if none resolves (no `--target`/persisted/configured default), stop and ask rather than picking a folder** (e.g. Drive root); a live fresh-context test confirmed an agent will otherwise improvise one. | `lark-cli docs +fetch --detail with-ids` (optionally `--scope outline`), extract each heading block's `id` and map it to the canonical schema's section name | `lark-cli docs +update` with a **block-scoped** op (`str_replace` on a specific block, or `block_replace`/`block_insert_after` bounded to the section's block range from `fetch_anchors`) — never `overwrite` on the whole doc. If the copied template pre-populates a section (e.g. "Approach #2") with no corresponding generated content, leave it untouched rather than deleting it. | `lark-cli drive file.comments list --params '{"file_token":...,"file_type":"docx"}'` (native API; the `lark-drive` skill's `+list-comments` shortcut may not exist in an older installed CLI — fall back to the native call). Each item's `is_solved` = resolved state; `reply_list.replies` array length = reply count. Map `extra.content_anchor_id` to the nearest section anchor. | `--as user` identity (per `lark-shared`). Load the `lark-doc` skill (XML syntax + block-ID-lifecycle rules) before any create/update call — do not hand-roll the XML. Diagrams: render via `lark-whiteboard` from generated mermaid, isolated per `rfc.md`'s degrade rule — confirmed working end-to-end in a live test. |
| `confluence` | **Contract stub — not implemented** (no CLI/MCP available in this environment to build/test against) | `POST /wiki/rest/api/content` with `type: page`, cloning from a blueprint/template `content_id` you configure | Confluence storage-format headings don't carry a stable id across re-saves the way Lark blocks do — **known limitation**: fall back to matching by heading *text* (the canonical section names) rather than a persisted id, and re-resolve on every publish | versioned `PUT /wiki/rest/api/content/{id}` scoped to the specific storage-format node under that heading, using the page's current `version.number` (Confluence requires the version number to increment atomically — refetch it immediately before each PUT) | `GET /wiki/rest/api/content/{id}/child/comment` (read-only) — Confluence's comment object has `resolutionStatus` (open/resolved) and its own reply thread; map both the same way as `lark`'s `is_solved`/reply-count. | OAuth 2.0 (3LO) or API token + email (Atlassian Cloud). A future implementer needs to pick one and store it via a secrets pattern (never in `pw.config.sh` in plaintext) before this row can move to Implemented. |
| `google-docs` | **Contract stub — not implemented** | `drive.files.copy` of a template Drive file id, into the Drive folder resolved per target | Google Docs has **no native heading-id concept** — **known limitation**: the template must have **named ranges** pre-placed at authoring time (`documents.batchUpdate` → `createNamedRange`) for each canonical section; `fetch_anchors` just reads the existing named-range ids, it can't invent them post-hoc | `documents.batchUpdate` with a `replaceNamedRangeContent`-style request scoped to that section's named range | Drive API `comments.list` on the file — each comment has a `resolved` boolean and a `replies` array; map both the same way as `lark`'s `is_solved`/reply-count. | OAuth 2.0 (a Google Cloud service account or user consent flow). A future implementer must also document the one-time step of placing named ranges in the template — this can't be scripted against an arbitrary existing doc. |
| `notion` | **Contract stub — not implemented** | Notion's API has **no page-duplicate endpoint** — **known limitation**: `create_from_template` must recreate the block tree by reading the template's `GET /v1/blocks/{id}/children` and re-`POST`ing each block under the new page, not a single copy call | Notion blocks have stable ids (unlike Confluence/Docs) — read them via `GET /v1/blocks/{id}/children`, map each top-level block matching a canonical heading to its id | `PATCH /v1/blocks/{id}` on the specific block(s) under that heading's id | `GET /v1/comments?block_id={id}` — **known limitation**: Notion comment threads have no distinct "resolved" flag the way Lark/Confluence/Docs do; a future implementer needs a documented convention (e.g. treat a thread with no new comments since last pull as settled, or require the human to delete/react to close it) before per-thread tracking here can work the same way. | Internal integration token (Bearer) scoped to the workspace; the target page must be explicitly shared with the integration first — call this out to a future implementer, it's a common setup trap. |
| _`<future>`_ | _stub or implemented_ | _…_ | _…_ | _…_ | _…_ | Add a row — no code change needed. |

## Adding a backend (extensibility — a real integration project, not a quick edit)

1. Add a row above with the 4 operations spelled out concretely (exact CLI/API calls), its auth
   mechanism, and any platform-specific limitation (anchor stability, template mechanics).
2. If it needs new config (a template id, a space/site key, credentials-by-reference), add it to
   `pw.config.example.sh`'s RFC block, nested under the backend name (`PW_RFC_<BACKEND>_*`), never
   a bare credential value in the tracked example — point at how the value should be supplied
   (env var, secrets manager), per this org's secure-credential-handling convention.
3. Flip its Status to **Implemented** once it's actually been run against a real (disposable) doc —
   don't mark it implemented on spec alone; the `update_section` guarantee (never orphan a comment)
   is the one thing worth empirically verifying before trusting a backend with a real RFC.

No `/pw-rfc` command-logic change is required to add a row — the command reads this file at
publish time.
