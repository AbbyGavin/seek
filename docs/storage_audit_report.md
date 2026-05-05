# FAIRDOM-SEEK Storage Backend Audit Report

**Branch:** `s3-support`  
**Date:** 2026-04-14  
**Audited against:** actual repository code  
**Scope:** All code paths that may assume local filesystem access for uploaded or generated files

---

## 1. Executive Summary

The storage abstraction layer (`Seek::Storage`, `LocalAdapter`, `S3Adapter`) is **well-designed and correctly implemented**. The core `ContentBlob` model properly routes main file I/O through the adapter and the central download/serve helper (`serve_blob_file`) handles both backends.

However, **nine confirmed critical issues** prevent the application from functioning with an S3 backend in production. They fall into four categories:

1. **Legacy download controllers** still call `content_blob.filepath` directly and pass the result to `send_file`.
2. **Snapshot ROBundle** opens the blob file by local path.
3. **Archive extraction** (zip, tgz, txz, 7z, bz2) reads directly from the local filepath.
4. **Workflow extraction** writes diagram files and RO-Crate zips to local-only paths and passes those paths to library calls.

All issues are fixable with the `with_temporary_copy` pattern that already exists on `ContentBlob`, or by calling `serve_blob_file` where it is already implemented. **No architectural changes are needed.**

**Readiness for S3 parity:** ~70%. Core upload/download/search/extraction and the new admin tooling are complete. The gaps are concentrated in workflow processing, archive handling, and three download endpoints.

---

## 2. Confirmed Remaining Issues

### 2.1 Legacy `filepath` in `help_attachments_controller`

| | |
|---|---|
| **Severity** | Critical |
| **File** | `app/controllers/help_attachments_controller.rb:11` |
| **Method** | `download` |

```ruby
send_file @content_blob.filepath, filename: ..., disposition: 'attachment'
```

`filepath` returns a local filesystem path. For S3, the file is not on disk — this raises `ActionController::MissingFile`.

**Fix:** Replace with `serve_blob_file(@content_blob, disposition: 'attachment')`, already available via `CommonSweepers` / `content_blob_common.rb`.

**New cycle needed:** Yes (Cycle 9 — Download endpoint cleanup)

---

### 2.2 Legacy `filepath` in `help_images_controller`

| | |
|---|---|
| **Severity** | Critical |
| **File** | `app/controllers/help_images_controller.rb:16,20` |
| **Method** | `view` |

```ruby
filepath = @content_blob.filepath          # line 16
send_file filepath, ...                    # line 20
```

Same problem as 2.1 — local path passed to `send_file`.

**Fix:** Use `serve_blob_file(@content_blob, disposition: 'inline')`.

**New cycle needed:** Yes (Cycle 9)

---

### 2.3 Legacy `filepath` in `snapshots_controller`

| | |
|---|---|
| **Severity** | Critical |
| **File** | `app/controllers/snapshots_controller.rb:57` |
| **Method** | `download` |

```ruby
send_file @content_blob.filepath, ...
```

**Fix:** Replace with `serve_blob_file(@content_blob, disposition: 'attachment')`.

**New cycle needed:** Yes (Cycle 9)

---

### 2.4 `Snapshot#research_object` opens blob by local path

| | |
|---|---|
| **Severity** | Critical |
| **File** | `app/models/snapshot.rb:75` |
| **Method** | `research_object` |

```ruby
def research_object
  ROBundle::File.open(content_blob.filepath) do |ro|
    yield ro if block_given?
  end
end
```

`ROBundle::File.open` is a file library that requires a local path. For S3, `filepath` returns a path that does not exist on disk.

**Fix:**
```ruby
def research_object
  content_blob.with_temporary_copy do |local_path|
    ROBundle::File.open(local_path) { |ro| yield ro if block_given? }
  end
end
```

**New cycle needed:** Yes (Cycle 10 — Snapshot S3 support)

---

### 2.5 Archive extraction reads directly from `filepath`

| | |
|---|---|
| **Severity** | Critical |
| **File** | `lib/seek/data_files/unzip.rb:27,34,40,49,58,64` |
| **Methods** | `unzip_zip`, `unzip_tar`, `unzip_bz2`, `unzip_tgz`, `unzip_txz`, `unzip_7z` |

All six methods open archives via `content_blob.filepath`:

```ruby
Zip::File.open(content_blob.filepath)            # line 27
unzip_tar(tmp_dir, input = content_blob.filepath) # line 34
Bzip2::FFI::Reader.open(content_blob.filepath)   # line 40
Zlib::GzipReader.open(content_blob.filepath)     # line 49
XZ::StreamReader.open(content_blob.filepath)     # line 58
SevenZipRuby::Reader.open_file(content_blob.filepath) # line 64
```

Archive libraries do not support S3 — they require a local file. With S3, `filepath` resolves to a nonexistent local path, causing `Errno::ENOENT`.

**Fix:** Wrap all formats with `with_temporary_copy`:
```ruby
def unzip_zip(tmp_dir)
  content_blob.with_temporary_copy do |local_path|
    Zip::File.open(local_path).entries.each { |f| ... }
  end
end
```

**New cycle needed:** Yes (Cycle 11 — Archive extraction S3 support)

---

### 2.6 Workflow diagram written to local-only path

| | |
|---|---|
| **Severity** | Critical |
| **File** | `app/models/concerns/workflow_extraction.rb:81–94` |
| **Methods** | `diagram`, `cached_diagram_path` |

```ruby
def diagram
  path = Dir.glob(cached_diagram_path('*')).last
  unless path && File.exist?(path)
    path = Pathname.new(cached_diagram_path(e.diagram_extension))
    path.parent.mkdir unless path.parent.exist?
    File.binwrite(path, diagram)          # writes to local filesystem only
  end
  WorkflowDiagram.new(self, path.to_s)
end

def cached_diagram_path(format)
  is_git_versioned? ?
    File.join(Seek::Config.converted_filestore_path, "git_version_#{id}_diagram.#{format}") :
    content_blob.filepath("diagram.#{format}")   # local-only path
end
```

For non-git workflows, `content_blob.filepath("diagram.#{format}")` returns a path in the converted filestore that does not exist on S3. The `File.binwrite` and `Dir.glob` calls will silently fail or raise for S3 backends.

**Fix:** Store diagrams via the adapter (`storage_adapter('svg').write(key, diagram)`) and serve via `with_temporary_copy_of_converted` when a local path is needed.

**New cycle needed:** Yes (Cycle 12 — Workflow diagram S3 support)

---

### 2.7 Workflow `populate_ro_crate` uses `filepath` for main workflow file

| | |
|---|---|
| **Severity** | Critical |
| **File** | `app/models/concerns/workflow_extraction.rb:140` |
| **Method** | `populate_ro_crate` |

```ruby
crate.main_workflow = ROCrate::Workflow.new(
  crate, content_blob.filepath,
  content_blob.original_filename,
  contentSize: content_blob.file_size
)
```

`ROCrate::Workflow.new` receives a local path. For S3, this file does not exist on disk.

**Fix:** Use `with_temporary_copy` to ensure a local file is available while the RO-Crate is being built, or stream the file content via the adapter.

**New cycle needed:** Yes (Cycle 12)

---

### 2.8 Workflow `ro_crate_path` for non-git blobs uses `filepath`

| | |
|---|---|
| **Severity** | Critical |
| **File** | `app/models/concerns/workflow_extraction.rb:299–303` |
| **Method** | `ro_crate_path` |

```ruby
def ro_crate_path
  is_git_versioned? ?
    File.join(Seek::Config.converted_filestore_path, "git_version_#{id}.crate.zip") :
    content_blob.filepath('crate.zip')    # local-only path
end
```

Used by `ro_crate_zip` (line 233) to check existence and build the zip. For S3, this path does not exist.

**Fix:** For non-git workflows, store the crate zip via the adapter (`storage_adapter('crate.zip')`) and use `file_exists?('crate.zip')` for the existence check.

**New cycle needed:** Yes (Cycle 12)

---

### 2.9 Avatar and model image uploads always write to local filesystem

| | |
|---|---|
| **Severity** | Medium (known architectural gap) |
| **Files** | `app/models/avatar.rb:8–16`, `app/controllers/avatars_controller.rb:50,56` |
| **Methods** | `Avatar` (model-level via `acts_as_fleximage`), `AvatarsController#show`, `AvatarsController#create` |

Avatar images are handled by the `acts_as_fleximage` plugin, which is **completely separate from the ContentBlob / `Seek::Storage` adapter system**. The storage path is configured independently:

```ruby
# app/models/avatar.rb
acts_as_fleximage do
  image_directory Seek::Config.avatar_filestore_path  # → filestore/avatars/
  image_storage_format :png
end
```

On upload (`create`), fleximage writes the PNG directly to `Seek::Config.avatar_filestore_path` on the local disk — no `ContentBlob`, no `Seek::Storage` adapter. On serve (`show`), the controller reads from `full_cache_path` (a local fleximage resize cache) and calls `send_file` directly:

```ruby
# app/controllers/avatars_controller.rb:56
send_file(@avatar.full_cache_path(size), type: "image/png", disposition: 'inline')
```

Additionally, `Avatar#public_asset_url` (line 55–58) uses `FileUtils.copy` from the resize cache to a public web directory — again, entirely local.

The same applies to `ModelImage` (`Seek::Config.model_image_filestore_path`) and its controller.

**This is a by-design separate storage system, not an oversight**, but it means avatars and model images are **not covered by the S3 adapter** and will remain on local disk even when a deployment switches ContentBlob storage to S3.

**Impact:** 
- Avatars will still function with S3 enabled for blobs (they don't share the adapter).
- In a fully containerised or distributed deployment (multiple app servers, no shared NFS), avatar files will not be accessible across nodes — this is the same problem that motivated the S3 work for blobs.
- The `seek:storage:copy_local_to_s3` migration rake task does **not** migrate avatars.

**Fix options:**
1. Migrate avatars to use `ContentBlob` + the `Seek::Storage` adapter (significant refactor of `acts_as_fleximage` integration).
2. Treat avatars as a separate migration concern: add a second rake task (`seek:storage:copy_avatars_to_s3`) and serve via a CDN or object store URL.
3. Accept local-only for avatars as a known limitation and document it.

**New cycle needed:** Yes — Cycle 14 (Avatar S3 support), deferred. Should be documented as a known limitation until addressed.

---

## 3. Likely or Suspicious Areas

### 3.1 RO-Crate export (`lib/seek/isa_ro_crate/`)

**Risk:** High  
Multiple files in `lib/seek/isa_ro_crate/` build RO-Crate archives that include blob data. The ISA RO-Crate exporter likely calls `content_blob.filepath` or `content_blob.file` in ways that assume local access. These paths were not changed in Cycles 1–8 and should be audited in full before S3 is enabled for production.

**Evidence:** The `workflow_extraction.rb` pattern of using `filepath` for RO-Crate suggests similar patterns may exist here.

---

### 3.2 Renderer stack (`lib/seek/renderers/`)

**Risk:** Medium  
Renderers that produce previews (PDF, notebook, SVG) may read blob content via local paths. The `BlobRenderer` base class and its subclasses should be checked for direct `filepath` usage. Content extraction (Docsplit, Libreconv) was updated in Cycle 6, but renderer serving paths may not be.

---

### 3.3 ZIP download for multi-file assets (`content_blob_common.rb:99`)

**Risk:** Low-Medium  
`make_and_send_zip_file` builds a `files_to_download` hash with:
```ruby
local_path = content_blob.storage_adapter.full_path(...) || content_blob.make_temp_copy
```
This is correct — `make_temp_copy` is the S3 fallback. However, the code is non-obvious and relies on callers building the hash correctly. For large files on S3, `make_temp_copy` downloads the entire file to disk first, which may cause memory/disk pressure.

**Assessment:** Functional but inefficient for S3 with large files.

---

### 3.4 Background jobs

**Risk:** Low  
Jobs in `app/jobs/` may read blob files for processing. Most jobs trigger model methods (content extraction, search reindex) which were updated in Cycles 5–6. However, any job that directly constructs file paths from `ContentBlob` attributes should be checked.

---

## 4. Confirmed Correct Areas

| Area | File(s) | Assessment |
|------|---------|------------|
| ContentBlob main file I/O | `app/models/content_blob.rb` | ✅ All reads/writes via adapter |
| Content extraction (search indexing) | `lib/seek/content_extraction.rb` | ✅ Patterns A/B/C all adapter-based |
| Single file download/serve | `lib/seek/content_blob_common.rb` → `serve_blob_file` | ✅ Local: `send_file`; S3: presigned redirect |
| PDF serving in UI | `app/controllers/content_blobs_controller.rb` → `serve_pdf` | ✅ Adapter-based |
| Storage config + validation | `lib/seek/storage.rb` + `config/initializers/seek_storage.rb` | ✅ Boot-time validation |
| S3 connectivity test | `lib/tasks/seek_storage.rake` → `seek:storage:test` | ✅ Functional |
| Admin storage status panel | `app/views/admin/_storage_status.html.erb` | ✅ No credentials exposed |
| Migration rake task | `lib/seek/storage/local_to_s3_migrator.rb` | ✅ Idempotent, dry-run, derivatives |
| `with_temporary_copy` | `app/models/content_blob.rb` | ✅ Correct S3 fallback |
| `with_temporary_copy_of_converted` | `app/models/content_blob.rb` | ✅ Correct S3 fallback |
| Storage adapter tests | `test/unit/seek/s3_adapter_test.rb` | ✅ 17 tests |
| Storage config tests | `test/unit/seek/storage_test.rb` | ✅ 9 tests |
| Content extraction tests | `test/unit/seek/content_extraction_test.rb` | ✅ 22 tests, incl. S3 stubs |
| Migration tests | `test/unit/seek/local_to_s3_migrator_test.rb` | ✅ 9 tests |

---

## 5. Naming and Structure Review

### Storage module

| Item | Path | Classification |
|------|------|---------------|
| Storage module | `lib/seek/storage.rb` | ✅ Correct |
| Local adapter | `lib/seek/storage/local_adapter.rb` | ✅ Correct |
| S3 adapter | `lib/seek/storage/s3_adapter.rb` | ✅ Correct |
| Migration service | `lib/seek/storage/local_to_s3_migrator.rb` | ✅ Correct |
| Rake tasks | `lib/tasks/seek_storage.rake` | ✅ Correct — follows `seek:storage:*` namespace |
| Example config | `config/seek_storage.yml.example` | ✅ Correct |
| Boot initializer | `config/initializers/seek_storage.rb` | ✅ Correct |

### Test locations

| Item | Path | Classification |
|------|------|---------------|
| S3 adapter tests | `test/unit/seek/s3_adapter_test.rb` | ⚠ Acceptable but inconsistent — see note |
| Storage config tests | `test/unit/seek/storage_test.rb` | ⚠ Acceptable but inconsistent |
| Content extraction tests | `test/unit/seek/content_extraction_test.rb` | ⚠ Acceptable but inconsistent |
| Migration tests | `test/unit/seek/local_to_s3_migrator_test.rb` | ⚠ Acceptable but inconsistent |

**Note on `test/unit/seek/`:** The SEEK project's existing test convention places tests for modules in `lib/seek/` directly in `test/unit/` with matching names (e.g., `test/unit/content_blob_test.rb`, not `test/unit/seek/content_blob_test.rb`). The new subdirectory `test/unit/seek/` is reasonable for the new `Seek::Storage` module family, but it is not fully consistent with the surrounding test suite. Keeping it as-is is acceptable since it groups the new storage tests cleanly.

### Admin views

| Item | Path | Classification |
|------|------|---------------|
| Storage status partial | `app/views/admin/_storage_status.html.erb` | ✅ Correct — follows Rails partial convention |

---

## 6. Missing Tests

### Critical (S3 will silently break without these)

1. **`help_attachments_controller#download` with S3 backend** — currently untested for S3; would catch the `filepath` bug.
2. **`snapshots_controller#download` with S3 backend** — same.
3. **`Snapshot#research_object` with S3 backend** — `ROBundle::File.open(filepath)` will raise.
4. **`DataFiles::Unzip` all formats with S3** — all `unzip_*` methods will raise for S3.
5. **`WorkflowExtraction#diagram` with S3** — `File.binwrite` to nonexistent path.
6. **`WorkflowExtraction#ro_crate_zip` with S3** — `filepath('crate.zip')` resolves to nonexistent path.
7. **`WorkflowExtraction#populate_ro_crate` with S3** — `ROCrate::Workflow.new(crate, filepath)` fails.

### Medium

8. **`serve_blob_file` for S3 — full controller integration test** — currently only unit-tested; no functional test verifies the presigned redirect end-to-end.
9. **`with_temporary_copy` cleanup** — verify temp files are always deleted, including on exception.
10. **`LocalToS3Migrator` with real ContentBlob records** — current tests use `MigratorBlobStub`; at least one test against an actual fixture blob would increase confidence.

---

## 7. Suggested Next Cycles

### Cycle 9 — Download endpoint cleanup (small, independent)

**Scope:**
- `help_attachments_controller.rb#download` — replace `filepath` with `serve_blob_file`
- `help_images_controller.rb#view` — replace `filepath` with `serve_blob_file`
- `snapshots_controller.rb#download` — replace `filepath` with `serve_blob_file`

**Tests:** Add functional tests verifying S3 redirect for each endpoint.  
**Effort:** 1 day.

---

### Cycle 10 — Snapshot ROBundle access

**Scope:**
- `snapshot.rb#research_object` — wrap with `with_temporary_copy`

**Tests:** Unit test `Snapshot#research_object` with a stubbed S3 adapter.  
**Effort:** Half a day.

---

### Cycle 11 — Archive extraction with S3

**Scope:**
- `lib/seek/data_files/unzip.rb` — all six `unzip_*` methods — wrap with `with_temporary_copy`

**Tests:** Test each archive format with a stubbed S3 adapter.  
**Effort:** 1 day.

---

### Cycle 12 — Workflow extraction with S3

**Scope:**
- `workflow_extraction.rb#cached_diagram_path` — store diagrams via `storage_adapter('svg')`
- `workflow_extraction.rb#diagram` — write via adapter, not `File.binwrite`
- `workflow_extraction.rb#populate_ro_crate` — wrap `content_blob.filepath` with `with_temporary_copy`
- `workflow_extraction.rb#ro_crate_path` — use `storage_adapter('crate.zip')` for non-git blobs

**Tests:** Test diagram generation and RO-Crate export with S3 backend.  
**Effort:** 2–3 days (most complex remaining gap).

---

### Cycle 13 — ISA RO-Crate and renderer audit (verify, fix if needed)

**Scope:**
- Audit `lib/seek/isa_ro_crate/` for direct `filepath` usage
- Audit `lib/seek/renderers/` for local path assumptions
- Fix any confirmed issues found

**Effort:** 1–2 days (mostly reading + targeted fixes).

---

## 8. Issue Priority Matrix

| # | Issue | Severity | Cycle | Effort |
|---|-------|----------|-------|--------|
| 2.1 | `help_attachments_controller#download` uses `filepath` | Critical | 9 | 1 hr |
| 2.2 | `help_images_controller#view` uses `filepath` | Critical | 9 | 1 hr |
| 2.3 | `snapshots_controller#download` uses `filepath` | Critical | 9 | 1 hr |
| 2.4 | `Snapshot#research_object` opens blob by local path | Critical | 10 | 2 hr |
| 2.5 | All `unzip_*` methods use `content_blob.filepath` | Critical | 11 | 1 day |
| 2.6 | `workflow_extraction#diagram` writes to local path | Critical | 12 | 2 days |
| 2.7 | `workflow_extraction#populate_ro_crate` uses `filepath` | Critical | 12 | 2 days |
| 2.8 | `workflow_extraction#ro_crate_path` uses `filepath` | Critical | 12 | 2 days |
| 3.1 | ISA RO-Crate exporter (unverified) | Likely | 13 | 1 day |
| 3.2 | Renderer stack (unverified) | Likely | 13 | 1 day |
| 3.3 | ZIP multi-file inefficiency for S3 | Low | — | — |
