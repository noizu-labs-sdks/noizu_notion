# File Uploads

Threat detail for T-006, T-007 — `Noizu.Notion.FileUploads`
(`lib/noizu/notion/file_uploads.ex`), the only multipart path in the library.

## Flow and where bytes live

```
caller binary  ──►  send_file(client, id, data: binary)
                         │  wrapped into Req form_multipart:
                         │  {"file", {data, [filename:, content_type:]}} (+ part_number field)
                         ▼
                    POST /v1/file_uploads/{id}/send   (multipart/form-data)
```

- `send_file/3` requires `:data` as a **binary** — the entire file (or part) is held in
  memory; there is no streaming/file-path option in v0.1.
- `create/2` declares mode (`single_part` default, `multi_part` for >20 MiB with 1–10 000
  parts, `external_url`), filename (≤900 bytes server-enforced), and content type.
- Attachment to pages/blocks happens later by ID — the library never handles the file
  content again after `send`.

## T-006 (Low) — whole-file buffering · Open (documented)

Multi-part mode exists precisely for large files, but every part is a full binary in the
calling process's heap. A host uploading many large parts concurrently can drive memory
pressure up quickly; there is no backpressure and no chunked read. Accepted for v0.1 and
documented in the register; a `send_file` variant accepting an enumerable/iodata or a
path would close it.

## T-007 (Low) — retry may re-send a part · Accepted

`send` is a POST, but the retry policy retries **429 and 529 on every method** (only
502/503/504 are restricted to idempotent methods). If a `send` request was processed
server-side but answered `529` (or a delayed `429`), the automatic retry sends the part
again. Bounding factors:

- a retried part carries the same `part_number`, so the server-side effect is an
  overwrite of that part, not duplication;
- Notion's documented semantics treat 429 as "not processed" and 529 as overload — the
  window for "processed then 529" is narrow;
- completion (`complete/2`) is a separate explicit step, so a torn multi-part upload
  surfaces at `retrieve/2` (`status: "failed"`, `number_of_parts`) rather than corrupting
  an attachment silently.

Residual risk accepted; callers needing exactly-once part delivery should disable retry
(`retry: [max_attempts: 0]`) for sends and drive retries themselves.

## Input handling around uploads

- `file_upload_id` goes through `Request.encode_segment/1` like every other path segment.
- `filename` and `content_type` opts are handed to Req's multipart encoder, which owns
  MIME boundary framing — no hand-built multipart body, so no header/boundary injection
  surface in this library.
- `part_number` is coerced via `Integer.to_string/1` and guarded by `is_integer/1`.
- `external_url` mode hands Notion a caller-chosen public HTTPS URL that **Notion's**
  infrastructure fetches — SSRF considerations live on Notion's side; this library only
  forwards the string in a JSON body. Consumers should not point `external_url` at
  internal endpoints out of caution for their own egress topology, but no fetch happens
  from this library or its host.

## What the library does not do

- No local temp files, no disk writes, no checksums computed or verified client-side
  (Notion's `file_import_result` reports server-side outcomes).
- No upload-size pre-checks — payload limits (500 KB request cap applies to JSON bodies;
  file parts are Notion's documented limits) are enforced server-side as 400s.
