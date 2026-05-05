**# Plan: Configurable file storage backends for FAIRDOM-SEEK
## Status: Cycles 1–8 done ✓

## Architecture summary

Introduce a **storage adapter** pattern behind a single `Seek::Storage` module. `ContentBlob` delegates all file I/O through this adapter rather than directly calling `File`, `FileUtils`, or `Seek::Config.asset_filestore_path`. Two concrete adapters ship: `LocalAdapter` (wraps current behaviour exactly) and `S3Adapter` (uses `aws-sdk-s3` with endpoint override for S3-compatible stores). The active adapter is chosen at boot from a new `config/seek_storage.yml` file. Local storage remains the default; nothing changes for existing deployments unless the admin opts in.

**Scope of current coupling (all must go through the adapter):**
- `ContentBlob#dump_data_object_to_file` — File.open write
- `ContentBlob#dump_tmp_io_object_to_file` — FileUtils.cp / chunked write
- `ContentBlob#file` — File.open read
- `ContentBlob#file_exists?` — File.exist?
- `ContentBlob#make_temp_copy` — FileUtils.cp to temp
- `ContentBlob#calculate_file_size` — File.size
- `ContentBlob#delete_converted_files` — FileUtils.rm
- `Seek::ContentExtraction` — File.read, Docsplit, Libreconv paths
- `Seek::RdfFileStorage` — File.open write/read/delete
- `Seek::DataFiles::Unzipper` — temporary file area
- `lib/seek/content_blob_common.rb` — `send_file` (local) vs presigned URL redirect (S3)

**What is NOT in scope (deferred):**
- Avatar / model image storage (fleximage gem handles separately)
- Git filestore (`git_filestore_path`) — complex, low priority
- RDF filestore — low volume, separate cycle
- Migration of existing files — separate tool, not runtime code
- Encryption key files — security-sensitive, keep local always

---

## Development cycles

---

### Cycle 1 — Characterise and add missing tests for current file I/O**

**Objective:** Before touching any storage code, lock down what ContentBlob does today with tests. This gives a safety net for all later cycles.

**Why now:** Every later cycle risks breaking file persistence. Tests written against current behaviour become the regression suite.

**Files likely to change:**
- `test/unit/content_blob_test.rb` (add tests)
- `test/unit/seek/content_extraction_test.rb` (add tests if missing)

**Implementation steps:**
1. Add test: `dump_data_object_to_file` writes a file at the expected UUID path
2. Add test: `dump_tmp_io_object_to_file` with a Tempfile (cp path) writes correctly
3. Add test: `dump_tmp_io_object_to_file` with a StringIO (no path) writes correctly
4. Add test: `file_exists?` returns true after save, false on new blob
5. Add test: `data_io_object` reads back what was written
6. Add test: `delete_converted_files` removes PDF/TXT variants
7. Add test: `calculate_file_size` sets `file_size` from disk after save

**Risks:** None — read-only changes to tests.

**Definition of done:** All new tests pass on current code.

**Suggested commit scope:** One PR: `test: characterise ContentBlob file I/O behaviour`

---

### Cycle 2 — Extract a `Seek::Storage::LocalAdapter` (pure refactor, no behaviour change)

**Objective:** Move all direct `File`/`FileUtils` calls in `ContentBlob` into a new `Seek::Storage::LocalAdapter` class. ContentBlob calls methods on the adapter. Behaviour is identical.

**Why now:** This is the preparatory refactor that makes the S3 adapter possible without touching ContentBlob again.

---

#### Step 2a — Create `lib/seek/storage/local_adapter.rb`

New file. Wraps the exact same logic currently inline in ContentBlob:

```ruby
# lib/seek/storage/local_adapter.rb
module Seek
  module Storage
    class LocalAdapter
      def initialize(base_path:)
        @base_path = base_path
      end

      # Write String or IO content to storage. key = "uuid.dat"
      def write(key, content)
        File.open(full_path(key), 'wb+') do |f|
          if content.respond_to?(:read)
            content.rewind
            until (chunk = content.read(ContentBlob::CHUNK_SIZE)).nil?
              f.write(chunk)
            end
          else
            f.write(content)
          end
        end
      end

      # Copy a file that already exists at local_src into storage
      def copy_from_path(local_src, key)
        FileUtils.cp(local_src, full_path(key))
      end

      # Returns a read-only File object. Caller must close it.
      def open(key)
        File.open(full_path(key), 'rb')
      end

      def exist?(key)
        File.exist?(full_path(key))
      end

      def delete(key)
        path = full_path(key)
        FileUtils.rm(path) if File.exist?(path)
      end

      def size(key)
        File.size(full_path(key))
      end

      # Returns the absolute filesystem path — used by send_file and make_temp_copy
      def full_path(key)
        File.join(@base_path, key)
      end
    end
  end
end
```

**Note:** Two separate adapters are needed: one for `asset_filestore_path` (`.dat` files) and one for `converted_filestore_path` (`.pdf`/`.txt` files). ContentBlob already routes by format in `filepath(format)` — we keep the same split.

---

#### Step 2b — Add `storage_key` and `storage_adapter` helpers to `ContentBlob` ✓ done (memoization fix pending)

`storage_key` is done. `storage_adapter` is written but currently allocates a new `LocalAdapter` on every call. Fix: memoize per adapter type (`:dat` vs `:converted`). Since pdf and txt share the same `converted_storage_directory`, only 2 adapter instances are ever created per blob.

```ruby
# In ContentBlob (app/models/content_blob.rb)

def storage_key(format = 'dat')
  storage_filename(format)  # already exists: returns "#{uuid}.#{format}"
end

def storage_adapter(format = 'dat')
  adapter_key = format == 'dat' ? :dat : :converted
  @storage_adapters ||= {}
  @storage_adapters[adapter_key] ||= begin
    base = format == 'dat' ? data_storage_directory : converted_storage_directory
    Seek::Storage::LocalAdapter.new(base_path: base)
  end
end
```

---

#### Step 2c — Replace the 7 direct File/FileUtils calls in ContentBlob

| Method | Before | After |
|---|---|---|
| `dump_data_object_to_file` | `File.open(filepath, 'wb+') { f.write(data) }` | `storage_adapter.write(storage_key, @data)` |
| `dump_tmp_io_object_to_file` (has path) | `FileUtils.cp(@tmp_io_object.path, filepath)` | `storage_adapter.copy_from_path(@tmp_io_object.path, storage_key)` |
| `dump_tmp_io_object_to_file` (no path) | `File.open(filepath, 'wb+') { chunked write }` | `storage_adapter.write(storage_key, @tmp_io_object)` |
| `data_io_object` | `File.open(filepath, 'rb')` | `storage_adapter.open(storage_key)` |
| `file_exists?(format)` | `File.exist?(filepath(format))` | `storage_adapter(format).exist?(storage_key(format))` |
| `calculate_file_size` | `File.size(filepath)` | `storage_adapter.size(storage_key)` |
| `delete_converted_files` | `FileUtils.rm(path) if File.exist?(path)` | `storage_adapter(format).delete(storage_key(format))` |
| `make_temp_copy` | `FileUtils.cp(filepath, temp_path)` | `FileUtils.cp(storage_adapter.full_path(storage_key), temp_path)` |

**Note:** `make_temp_copy` still calls `FileUtils.cp` since it's copying to a *local* temp path — that's fine for now. We just get the source path from the adapter (`full_path`) instead of calling `filepath` directly. This keeps it working and will be easy to swap in Cycle 6 for S3.

---

#### Step 2d — Fix memoization, then run tests

Apply the memoized `storage_adapter` from Step 2b above, then verify:

```bash
bundle exec rails test test/unit/content_blob_test.rb --name "/storage_filename|dump_data_object|dump_tmp_io_object|delete_converted_files|make_temp_copy|calculate_file_size|file_exists|storage_directory/"
```

All 10 characterisation tests + existing storage tests must pass.

---

**Files to create/change:**
- `lib/seek/storage/local_adapter.rb` ← created ✓
- `app/models/content_blob.rb` ← 7 file I/O calls replaced ✓, memoization pending

**Definition of done:** All Cycle 1 + existing ContentBlob tests pass. No `File.open`/`FileUtils.cp`/`File.exist?`/`File.size`/`FileUtils.rm` calls remain in the 7 methods listed above. `storage_adapter` memoizes — at most 2 `LocalAdapter` instances per blob.

**Suggested commit:** `refactor: extract Seek::Storage::LocalAdapter from ContentBlob`

**Gap found during UI testing — `lib/seek/data/checksums.rb`:**

`Seek::Data::Checksums#calculate_checksum` (line 40) calls `Digest::MD5.file(filepath)` directly, bypassing the adapter. Fix: replace with adapter-aware streaming using `storage_adapter.open(storage_key)`:

```ruby
def calculate_checksum(digest_type)
  return unless file_exists?
  digest = "Digest::#{digest_type.upcase}".constantize.new
  io = storage_adapter.open(storage_key)
  while (chunk = io.read(1_048_576))
    digest.update(chunk)
  end
  send("#{digest_type.to_s.downcase}sum=", digest.hexdigest)
end
```

This concern is included into `ContentBlob`, so `storage_adapter` and `storage_key` are already available. The `Digest` API supports streaming via `#update(chunk)` — no need to load the entire file into memory.

---

### Cycle 3 — Add `Seek::Storage` module with adapter registry and configuration loading

**Objective:** Add `Seek::Storage.adapter_for(format)` — a lazy, format-aware adapter registry backed by `config/seek_storage.yml`. No initializer; config loads on first call.

**Why now:** Needed before Cycle 4 (S3Adapter). Also simplifies `ContentBlob#storage_adapter` — per-instance memoization becomes redundant once the registry memoizes at process level.

**Design rationale:**
- **`adapter_for(format)` not `adapter`:** SEEK has two storage roots (`asset_filestore_path` for `.dat`, `converted_filestore_path` for converted files). The registry picks the backend *class* from config; format determines the *base path* (local) or *key prefix* (S3).
- **No initializer:** Config is loaded lazily on first `adapter_for` call. Avoids `Seek::Config` load-order problems; tests call `reset!` to force reload.
- **Missing `storage.yml` is safe:** Falls back to local backend — no `Errno::ENOENT` for existing deployments.
- **`aliases: true`:** Required for Psych 4+ (Ruby ≥ 3.1) to parse `<<: *default` merge keys in `safe_load`.
- **Namespace file required:** Zeitwerk autoloads `lib/seek/storage/` as a directory. To add class methods to `Seek::Storage`, `lib/seek/storage.rb` must exist as the namespace file.

---

**Files to change:**
- `lib/seek/storage.rb` (new — namespace file with class methods)
- `app/models/content_blob.rb` — simplify `storage_adapter` to one-liner delegate
- `config/seek_storage.yml` (new, committed with local default)
- No initializer needed

---

**`config/seek_storage.yml`:**

```yaml
default: &default
  backend: local

development:
  <<: *default

test:
  <<: *default

production:
  <<: *default
  # To switch to S3-compatible storage, uncomment and fill in:
  # backend: s3
  # bucket: my-seek-bucket
  # region: us-east-1
  # access_key_id: AKIAIOSFODNN7EXAMPLE
  # secret_access_key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  # endpoint: https://minio.example.com   # omit for AWS S3
  # force_path_style: true                # required for MinIO
```

---

**`lib/seek/storage.rb`:**

```ruby
module Seek
  module Storage
    # Returns the adapter for the given file format.
    # 'dat' → asset_filestore_path (or S3 'assets/' prefix)
    # any other format → converted_filestore_path (or S3 'converted/' prefix)
    # Memoized at module level — at most 2 adapter instances per process.
    def self.adapter_for(format = 'dat')
      adapter_key = format == 'dat' ? :dat : :converted
      @adapters ||= {}
      @adapters[adapter_key] ||= build_adapter_for(adapter_key)
    end

    # Reset all memoized state. Call in tests that swap config or paths.
    def self.reset!
      @adapters = nil
      @config   = nil
    end

    class << self
      private

      def build_adapter_for(adapter_key)
        cfg = config
        case cfg[:backend]
        when 's3'
          require 'seek/storage/s3_adapter'
          prefix = adapter_key == :dat ? 'assets' : 'converted'
          S3Adapter.new(cfg.merge(prefix: prefix))
        else
          base = adapter_key == :dat ? Seek::Config.asset_filestore_path
                                     : Seek::Config.converted_filestore_path
          LocalAdapter.new(base_path: base)
        end
      end

      def config
        @config ||= load_config
      end

      def load_config
        path = Rails.root.join('config', 'storage.yml')
        return { backend: 'local' } unless path.exist?

        raw = YAML.safe_load(
          ERB.new(File.read(path)).result,
          aliases: true
        )
        (raw[Rails.env] || raw['default'] || {}).symbolize_keys
      end
    end
  end
end
```

---

**ContentBlob simplification** — replace the `@storage_adapters` hash with a one-liner delegate:

```ruby
# app/models/content_blob.rb
def storage_adapter(format = 'dat')
  Seek::Storage.adapter_for(format)
end
```

Remove the `@storage_adapters ||= {}` memoization block — `Seek::Storage` handles it at process level.

---

**Tests to add (`test/unit/seek/storage_test.rb`, new file):**

```ruby
test 'adapter_for dat returns a LocalAdapter with asset_filestore_path'
test 'adapter_for pdf returns a LocalAdapter with converted_filestore_path'
test 'adapter_for dat is memoized — same object on repeated calls'
test 'adapter_for pdf and adapter_for txt return the same object (shared :converted key)'
test 'reset! clears memoized adapters and config'
test 'load_config returns local backend when storage.yml is absent'
```

---

**Risks:**
- `Seek::Config.asset_filestore_path` must return the correct path at time of first `adapter_for` call. In practice, `Seek::Config` is fully loaded before any request or job accesses storage — safe.
- `YAML.safe_load` with `aliases: true` and no `permitted_classes` is intentional: the YAML has no Ruby-specific types; we symbolize keys in Ruby, not in the YAML.

**Definition of done:** `Seek::Storage.adapter_for('dat')` and `adapter_for('pdf')` return memoized `LocalAdapter` instances with correct base paths. All Cycle 1+2 tests still pass. `reset!` is callable from tests.

**Suggested commit:** `feat: add Seek::Storage adapter registry with adapter_for and storage.yml config`

---

### Cycle 4 — Implement `Seek::Storage::S3Adapter`

**Objective:** Add `Seek::Storage::S3Adapter` matching the `LocalAdapter` interface exactly. Introduces `aws-sdk-s3`. No controller or download wiring — that is Cycle 5.

**Why now:** Foundation (Cycles 1–3) is solid; only now is it safe to add the new backend.

---

**Files to change:**
- `Gemfile` — add `gem 'aws-sdk-s3', require: false`
- `lib/seek/storage/s3_adapter.rb` (new)
- `test/unit/seek/s3_adapter_test.rb` (new)

---

**Interface contract** — must match `LocalAdapter` method-for-method:

| Method | LocalAdapter | S3Adapter |
|---|---|---|
| `write(key, content)` | `File.open` write or chunked | `put_object(bucket:, key: object_key(key), body:)` |
| `copy_from_path(src, key)` | `FileUtils.cp` | `File.open(src) { put_object(..., body: f) }` |
| `open(key)` | `File.open(..., 'rb')` | `get_object` → `body` (StringIO) |
| `exist?(key)` | `File.exist?` | see below — defensive `head_object` |
| `delete(key)` | `FileUtils.rm if exist?` | `delete_object` (S3 delete is idempotent; no guard needed) |
| `size(key)` | `File.size` | `head_object.content_length` |
| `full_path(key)` | `File.join(base, key)` | `nil` — S3 has no local path; callers that need a local path (e.g. `make_temp_copy`) will be updated in Cycle 6 |
| `presigned_url(key, expires_in:)` | *(not on LocalAdapter)* | `presigner.presigned_url(:get_object, ...)` |

**`exist?` — defensive not-found handling:**

`head_object` raises different errors depending on SDK version and server:
- `Aws::S3::Errors::NoSuchKey` — some SDK versions / some S3-compatible stores
- `Aws::S3::Errors::NotFound` — AWS S3 canonical 404 on HEAD
- `Aws::S3::Errors::Forbidden` (403) — can occur when object absent on some policy configs

Rescue all three plus the general `ServiceError` with a status-code check:

```ruby
def exist?(key)
  @client.head_object(bucket: @bucket, key: object_key(key))
  true
rescue Aws::S3::Errors::NotFound,
       Aws::S3::Errors::NoSuchKey,
       Aws::S3::Errors::Forbidden
  false
rescue Aws::S3::Errors::ServiceError => e
  raise unless e.context.http_response.status_code == 404
  false
end
```

---

**`object_key(key)` — prefix routing:**

Objects are namespaced under a prefix set at construction time (`'assets'` or `'converted'`), mirroring the local subdirectory split:

```ruby
def object_key(key)
  "#{@prefix}/#{key}"   # e.g. "assets/uuid.dat", "converted/uuid.pdf"
end
```

---

**Constructor and client:**

```ruby
def initialize(bucket:, prefix:, region: 'us-east-1',
               access_key_id: nil, secret_access_key: nil,
               endpoint: nil, force_path_style: false, **_rest)
  @bucket = bucket
  @prefix = prefix
  @client = Aws::S3::Client.new(
    region: region,
    access_key_id: access_key_id,
    secret_access_key: secret_access_key,
    endpoint: endpoint,
    force_path_style: force_path_style
  ).tap { |c| c.config.credentials  }  # eager credential check omitted — lazy is fine
end
```

Accept `**_rest` to swallow the `:backend` key that `Seek::Storage` passes through from config.

---

**Tests (`test/unit/seek/s3_adapter_test.rb`):**

Use `aws-sdk-s3`'s built-in stub mode (`Aws.config[:stub_responses] = true`) — no network, no MinIO needed for unit tests.

Tests to write:

```ruby
test 'write with String body calls put_object'
test 'write with IO body calls put_object'
test 'copy_from_path reads file and calls put_object'
test 'open returns a readable IO object'
test 'exist? returns true when head_object succeeds'
test 'exist? returns false on NotFound'
test 'exist? returns false on NoSuchKey'
test 'exist? returns false on 404 ServiceError'
test 'delete calls delete_object'
test 'size returns content_length from head_object'
test 'full_path returns nil'
test 'presigned_url returns a URL string containing the key'
```

**Stubbing pattern:**

```ruby
def setup
  require 'aws-sdk-s3'
  Aws.config.update(stub_responses: true)
  @adapter = Seek::Storage::S3Adapter.new(
    bucket: 'test-bucket', prefix: 'assets',
    region: 'us-east-1',
    access_key_id: 'test', secret_access_key: 'test'
  )
end

def teardown
  Aws.config.update(stub_responses: false)
end
```

Stub specific responses with `@adapter.send(:client).stub_responses(:head_object, 'NotFound')` for not-found tests.

---

**Risks:**
- `full_path` returning `nil` will break `make_temp_copy` in `ContentBlob` if S3 is active — that is intentionally deferred to Cycle 6. For now, `make_temp_copy` is only called for local blobs.
- `Aws.config[:stub_responses]` is global — always reset in `teardown`.
- `aws-sdk-s3` must be `require: false` in Gemfile; only loaded when `backend: s3` in `seek_storage.yml` or when the test explicitly requires it.

**Definition of done:** All 12 S3Adapter tests pass with stubbed AWS. `Seek::Storage.adapter_for('dat')` still returns `LocalAdapter` (no `seek_storage.yml` change). No controller or download changes.

**Suggested commit:** `feat: add Seek::Storage::S3Adapter with S3-compatible backend`

---

### Cycle 4b — MinIO live smoke test (optional, one-off)

**Objective:** Run the S3Adapter against a real MinIO server to confirm correct behaviour with an actual S3-compatible endpoint before wiring it into the app.

**Prerequisites:** MinIO running on `localhost:9000` with:
- `MINIO_ROOT_USER=seek`
- `MINIO_ROOT_PASSWORD=seek1234`
- Started with: `docker run -p 9000:9000 -p 9001:9001 -e MINIO_ROOT_USER=seek -e MINIO_ROOT_PASSWORD=seek1234 -v minio-seek-data:/data quay.io/minio/minio server /data --console-address ":9001"`

**Script location:** `script/minio_smoke_test.rb`

**What the script exercises:**
1. Create bucket `seek-smoke-test` (idempotent)
2. `write(key, String)` — write a string
3. `exist?(key)` → true
4. `size(key)` → correct byte count
5. `open(key)` → reads back original content
6. `copy_from_path(local_file, key2)` — upload from a Tempfile
7. `exist?(key2)` → true
8. `exist?('missing-key')` → false (tests not-found handling)
9. `delete(key)` — remove first object
10. `exist?(key)` → false after delete
11. `presigned_url(key2, expires_in: 60)` → URL string (verified with curl)
12. Cleanup: delete key2 and bucket

**Script design** (standalone, no Rails stack):
```ruby
#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'aws-sdk-s3'
require 'seek/storage/s3_adapter'
require 'tempfile'

BUCKET = 'seek-smoke-test'
KEY    = 'smoke/test.dat'
KEY2   = 'smoke/copy.dat'

adapter = Seek::Storage::S3Adapter.new(
  bucket:            BUCKET,
  prefix:            '',          # no prefix for smoke test — keys are literal
  region:            'us-east-1',
  access_key_id:     'seek',
  secret_access_key: 'seek1234',
  endpoint:          'http://localhost:9000',
  force_path_style:  true
)

# Create bucket directly via client (not part of adapter interface)
client = Aws::S3::Client.new(
  region: 'us-east-1', access_key_id: 'seek', secret_access_key: 'seek1234',
  endpoint: 'http://localhost:9000', force_path_style: true
)
client.create_bucket(bucket: BUCKET) rescue nil

content = 'Hello from SEEK S3Adapter smoke test'

pass = 0; fail = 0
def check(label, result)
  if result
    puts "  PASS  #{label}"
    pass += 1
  else
    puts "  FAIL  #{label}"
    fail += 1
  end
end
# ... exercises each method and prints PASS/FAIL
```

**Note on prefix:** the smoke test uses `prefix: ''` so keys are written literally as `smoke/test.dat`. In production, `Seek::Storage` always passes `'assets'` or `'converted'` as prefix, so the real objects are namespaced. The smoke test bypasses this to keep keys readable in the MinIO console.

**How to run:**
```bash
rvm use ruby-3.3.10
bundle exec ruby script/minio_smoke_test.rb
```

**Definition of done:** All 12 smoke checks print `PASS`. No errors raised against live MinIO.

**Known issue with seek_storage.yml for UI testing:** The S3 config must be a top-level key, not nested inside `default:`. Correct development config:

```yaml
default: &default
  backend: local

development:
  backend: s3
  bucket: seek-dev
  region: us-east-1
  access_key_id: seek
  secret_access_key: seek1234
  endpoint: http://localhost:9000
  force_path_style: true

test:
  <<: *default

production:
  <<: *default
```

After editing the file, restart the Rails server — `Seek::Storage` is memoized and won't re-read config without a restart.

---

### Cycle 5 — Wire download/streaming through the adapter

**Objective:** `send_file` only works for local storage. When S3 is active, downloads must redirect to a presigned URL or stream via the adapter.

**Why now:** Cycle 2 made file reads go through the adapter, but `ContentBlobCommon#handle_download` still calls `send_file filepath` directly.

**Files to change:**
- `lib/seek/content_blob_common.rb` — `handle_download`
- `lib/seek/storage/local_adapter.rb` — add `serve_to_controller(controller, filepath, options)`
- `lib/seek/storage/s3_adapter.rb` — add `serve_to_controller(controller, key, options)`

**Pattern:**

```ruby
# content_blob_common.rb
def handle_download(disposition, image_size = nil)
  if content_blob.file_exists?
    storage_adapter.serve_to_controller(
      self,
      content_blob.storage_key,
      filename: content_blob.original_filename,
      type: content_blob.content_type,
      disposition: disposition
    )
  else
    stream_remote_or_error
  end
end
```

**LocalAdapter#serve_to_controller:**
```ruby
def serve_to_controller(controller, key, options)
  controller.send_file local_path(key), options
end
```

**S3Adapter#serve_to_controller:**
```ruby
def serve_to_controller(controller, key, options)
  url = presigned_url(key, expires_in: 300)
  controller.redirect_to url, allow_other_host: true
end
```

**Risks:**
- Presigned URL redirect changes browser URL; Content-Disposition header must be embedded in presigned URL params.
- ZIP downloads pull multiple content_blobs — each needs a `copy_to_tempfile` call, then zip from tempfiles. Already handled by `make_and_send_zip_file` via `make_temp_copy`.

**Definition of done:** Functional test: downloading a file with local adapter uses `send_file`; with S3 adapter (stubbed) issues a redirect.

**Suggested commit scope:** One PR: `feat: route ContentBlob downloads through storage adapter`

---

### Cycle 5b — Fix `ContentBlob#file` and `view_content` for S3

**Objective:** The `view_content` action (inline file preview) is broken with S3 because `ContentBlob#file` opens the local filepath directly, bypassing the adapter. All content renderers call `blob.read`, which delegates to this method.

**Root cause found during UI testing:**

`app/models/content_blob.rb` has:
```ruby
delegate :read, :close, :rewind, :path, to: :file

def file
  @file ||= File.open(filepath)   # ← bypasses adapter entirely
end
```

`lib/seek/renderers/` (TextRenderer, MarkdownRenderer, NotebookRenderer) all call `blob.read`.
`app/controllers/content_blobs_controller.rb` `csv_data` action calls `File.read(@content_blob.filepath, encoding: 'iso-8859-1')` directly.

**Files to change:**
- `app/models/content_blob.rb` — `file` method, delegate list
- `app/controllers/content_blobs_controller.rb` — `csv_data` action

**Implementation:**

1. Change `ContentBlob#file` to use the adapter:
```ruby
def file
  @file ||= storage_adapter.open(storage_key)
end
```
`LocalAdapter#open` returns a `File` object (has `.path`). `S3Adapter#open` returns `StringIO` (no `.path`).

2. Remove `:path` from the delegate (StringIO doesn't have it) and expose it separately:
```ruby
delegate :read, :close, :rewind, to: :file

def path
  storage_adapter.full_path(storage_key)   # nil for S3 — same as full_path convention
end
```

3. Fix `csv_data` in `ContentBlobsController` — replace `File.read(@content_blob.filepath, encoding: 'iso-8859-1')` with:
```ruby
render plain: @content_blob.file.read.encode('utf-8', 'iso-8859-1', invalid: :replace, undef: :replace)
```
(or simply `@content_blob.data_io_object` if encoding is handled elsewhere)

**Note on `@file` memoization:** `@file` is an instance-level cache on the ContentBlob object. After `read`, the IO is positioned at EOF. Any subsequent `read` call needs a `rewind` first — but this is existing behaviour (unchanged).

**Definition of done:** Uploading a text/CSV/markdown file and clicking "View content" renders the file inline without error. Existing renderer tests pass.

**Suggested commit:** `fix: route ContentBlob#file and csv_data through storage adapter`

---

### Cycle 6 — Wire `Seek::ContentExtraction` through the storage adapter

**Objective:** Fix all 8 direct `File`/`FileUtils` call sites in `lib/seek/content_extraction.rb` so that search indexing and text extraction work when S3 is the active backend.

**Why now:** `pdf_contents_for_search` and `text_contents_for_search` are invoked from background indexing jobs. With S3 active and no local copy present, they currently raise or silently return empty content. This is the first user-visible breakage after the adapter is switched on.

---

#### User-visible outcome

**What Cycle 6 enables for S3-backed files:**
- Full-text search indexing works: PDFs are converted, text is extracted, and results are stored back to S3 — all without a local filestore.
- `text_contents_for_search` reads text files directly from S3 via the adapter.
- Spreadsheet content (`to_csv`, `to_spreadsheet_xml`) is streamed from S3 to SysMODB without a local temp copy.

**What is explicitly deferred to Cycle 6b:**
- `pdf_or_convert` in `app/controllers/content_blobs_controller.rb` still uses `filepath` and `send_file` directly. The **"Download as PDF"** button and inline PDF viewer remain broken with S3 until Cycle 6b. This is a controller-level download concern, parallel to what Cycle 5 fixed for binary files.

**Parity note:** Cycle 6 restores conversion/extraction parity — background indexing and search work end-to-end with S3. Controller/view-serving parity (the PDF download and viewer) is deferred to Cycle 6b.

---

#### Abstraction boundary: use existing ContentBlob primitives, not the adapters directly

`ContentExtraction` is a module mixed into `ContentBlob`. It already has access to everything it needs:

| Primitive | What it does | S3-aware? |
|-----------|-------------|-----------|
| `data_io_object` | Returns an open IO for the `.dat` file | ✅ calls `storage_adapter.open` |
| `storage_adapter(format)` / `storage_key(format)` | Direct access to the adapter for a given format | ✅ |
| `with_temporary_copy { \|path\| }` | Yields a guaranteed local filesystem path, cleans up after | ✅ streams from S3 via `make_temp_copy` when `full_path` is nil |

**Do not add `with_local_copy` to the adapters.** That was considered and rejected: it duplicates `with_temporary_copy` at the wrong layer and forces `ContentExtraction` to reach into the adapter API unnecessarily.

---

#### Implementation patterns

There are three distinct patterns across the 8 call sites. Each method maps cleanly to one of them.

---

##### Pattern A — Simple reads: replace `File.read(filepath)` with `data_io_object`

These methods only need to read the raw file content. `data_io_object` returns a working IO for both local and S3. SysMODB's `SpreadsheetExtractor` explicitly accepts "an IO like object or path to a file" — confirmed in the gem source (`extractor.rb`: `if spreadsheet_data.is_a?(IO) || spreadsheet_data.is_a?(StringIO)`). No temp copy is needed.

| Method | Before | After |
|--------|--------|-------|
| `text_contents_for_search` | `File.read(filepath, encoding: 'iso-8859-1')` | `data_io_object.read.force_encoding('iso-8859-1')` |
| `extract_csv` | `File.read(filepath)` | `data_io_object.read` |
| `to_csv` | `spreadsheet_to_csv(filepath, sheet, trim, ...)` | `spreadsheet_to_csv(data_io_object, sheet, trim, ...)` |
| `to_spreadsheet_xml` | `spreadsheet_to_xml(filepath, ...)` | `spreadsheet_to_xml(data_io_object, ...)` |

`data_io_object` opens a fresh IO handle on each call. Each of these methods calls it once and reads it fully — that is safe. No rewind needed.

---

##### Pattern B — Derivative-file checks and reads: use `storage_adapter(format)` directly

These methods check whether a converted file (`.pdf`, `.txt`) exists in storage or read it back. Replace `File.exist?`/`File.read` on hard-coded converted paths with adapter calls.

| Method | Before | After |
|--------|--------|-------|
| `pdf_contents_for_search` — already-PDF dat | `FileUtils.cp filepath, filepath('pdf')` | `storage_adapter('pdf').write(storage_key('pdf'), data_io_object)` |
| `extract_text_from_pdf` — PDF guard | `File.exist?(pdf_filepath)` | `storage_adapter('pdf').exist?(storage_key('pdf'))` |
| `extract_text_from_pdf` — TXT guard | `File.exist?(txt_filepath)` | `storage_adapter('txt').exist?(storage_key('txt'))` |
| `extract_text_from_pdf` — TXT read | `File.read(txt_filepath)` | `storage_adapter('txt').open(storage_key('txt')).read` |

---

##### Pattern C — PDF conversion pipeline: `with_temporary_copy` + write-back

`convert_to_pdf` and the Docsplit step in `extract_text_from_pdf` require real filesystem paths for external tools (Libreconv, Docsplit). The pattern:

1. **Source dat input**: `with_temporary_copy { |dat_path| ... }` — already S3-aware, no change to the helper needed.
2. **Libreconv output**: run into a `Tempfile`, then write back via `storage_adapter('pdf').write(...)`.
3. **Docsplit output**: Docsplit writes to a directory, not a single file. Run into `Dir.mktmpdir`, find the resulting `.txt`, write it back via `storage_adapter('txt').write(...)`. The PDF input to Docsplit also needs a local path — use a second `with_temporary_copy_of_converted('pdf')` call (see below).

Both `Tempfile` and `Dir.mktmpdir` clean up automatically when used with a block. The inner dat staging file (`Tempfile.new`) uses `ensure { tmp_dat.close! }` explicitly since Libreconv may leave it open.

```ruby
# convert_to_pdf — new shape (no arguments, adapter-based)
def convert_to_pdf
  return if storage_adapter('pdf').exist?(storage_key('pdf'))

  Rails.logger.info("Converting blob #{id} to pdf")
  file_ext = mime_extensions(content_type).first

  with_temporary_copy do |dat_path|
    Tempfile.create(['converted', '.pdf']) do |pdf_tmp|
      tmp_dat = Tempfile.new(['', ".#{file_ext}"])
      begin
        FileUtils.cp(dat_path, tmp_dat.path)
        Libreconv.convert(tmp_dat.path, pdf_tmp.path)
        pdf_tmp.rewind
        storage_adapter('pdf').write(storage_key('pdf'), pdf_tmp)
      ensure
        tmp_dat.close!
      end
    end
  end
rescue StandardError => e
  Seek::Errors::ExceptionForwarder.send_notification(e, data: { content_blob: self, asset: asset })
  Rails.logger.error("Problem converting blob #{id} to pdf — #{e.class.name}: #{e.message}")
end
```

```ruby
# extract_text_from_pdf — Docsplit step
Dir.mktmpdir('docsplit-txt') do |tmp_dir|
  with_temporary_copy_of_converted('pdf') do |pdf_path|
    Docsplit.extract_text(pdf_path, output: tmp_dir)
    txt_path = Dir["#{tmp_dir}/*.txt"].first
    storage_adapter('txt').write(storage_key('txt'), File.open(txt_path, 'rb')) if txt_path
  end
end
```

`with_temporary_copy_of_converted(format)` is a small private helper on `ContentBlob`, alongside `with_temporary_copy`. It mirrors the same pattern but reads from the converted store:

```ruby
# app/models/content_blob.rb (private)
def with_temporary_copy_of_converted(format)
  local = storage_adapter(format).full_path(storage_key(format))
  if local
    yield local
  else
    Tempfile.create(["converted-#{format}", ".#{format}"]) do |tmp|
      IO.copy_stream(storage_adapter(format).open(storage_key(format)), tmp)
      tmp.flush
      yield tmp.path
    end
  end
end
```

---

#### `convert_to_pdf` signature: keep backward-compatible default arguments

The current signature is `def convert_to_pdf(dat_filepath = filepath, pdf_filepath = filepath('pdf'))`. The controller's `pdf_or_convert` (deferred to Cycle 6b) still calls `convert_to_pdf(filepath, pdf_filepath)` with explicit local paths.

**Do not remove the arguments in Cycle 6.** Instead, make the method detect which path it is on:

```ruby
def convert_to_pdf(dat_filepath = nil, pdf_filepath = nil)
  if dat_filepath || pdf_filepath
    # Legacy local-path call from pdf_or_convert (controller).
    # Still uses the old File.exist?/Libreconv/FileUtils approach until Cycle 6b.
    legacy_convert_to_pdf(dat_filepath || filepath, pdf_filepath || filepath('pdf'))
  else
    # Adapter-based path (Pattern C above).
    adapter_convert_to_pdf
  end
end
```

Extract the existing implementation into `legacy_convert_to_pdf` (private) unchanged. Implement `adapter_convert_to_pdf` (private) as the new Pattern C code. After Cycle 6b updates the controller to stop passing arguments, both `legacy_convert_to_pdf` and the argument branch can be deleted.

This avoids breaking the `pdf_or_convert` controller path during Cycle 6, while making the no-argument call adapter-aware immediately.

---

#### Concurrency (document, do not fix)

The `storage_adapter('pdf').exist?` guard in `convert_to_pdf` is a TOCTOU race: two background jobs can both observe the PDF absent and both start converting. The race was present before (using `File.exist?`) and is unchanged here. It is harmless — last write wins, both jobs produce identical output. A proper fix would require distributed locking (Redis, DB advisory lock) and is out of scope. Document in a comment near the guard.

---

#### Files to change

| File | Change |
|------|--------|
| `lib/seek/content_extraction.rb` | 8 call sites across patterns A, B, C; split `convert_to_pdf` into `legacy_convert_to_pdf` + `adapter_convert_to_pdf` |
| `app/models/content_blob.rb` | Add `with_temporary_copy_of_converted(format)` private helper |

**Not changing in this cycle:**
- `lib/seek/storage/local_adapter.rb` — no new methods needed
- `lib/seek/storage/s3_adapter.rb` — no new methods needed
- `lib/seek/content_blob_common.rb` — resolved in Cycle 5
- `app/controllers/content_blobs_controller.rb` — deferred to Cycle 6b

---

#### Tests

Create `test/unit/seek/content_extraction_test.rb`. No such file currently exists. Structure tests by pattern. Local backend tests use the normal test environment (seek_storage.yml test env defaults to local). S3 tests stub `Seek::Storage` to return an `S3Adapter` with `Aws.config[:stub_responses] = true`.

---

**Pattern A — Simple reads (local backend)**

```
test 'text_contents_for_search reads content from adapter IO'
  # use :txt_content_blob factory; assert returned array includes the file's text
  # verifies data_io_object.read.force_encoding path

test 'to_csv returns CSV string via data_io_object'
  # use an xlsx/csv fixture blob; assert result is non-empty CSV string

test 'to_spreadsheet_xml returns XML string via data_io_object'
  # use an xlsx fixture blob; assert result contains <workbook or equivalent root
```

**Pattern A — Simple reads (stubbed S3)**

```
test 'text_contents_for_search reads from S3 adapter when backend is S3'
  # stub Seek::Storage to return S3Adapter; stub get_object → "hello world"
  # assert result includes filtered "hello world"
  # ensures data_io_object uses the adapter, not File.open(filepath)
```

---

**Pattern B — Derivative-file existence and reads (local backend)**

```
test 'pdf_contents_for_search for an already-PDF dat writes dat content to pdf key'
  # use :pdf_content_blob; assert storage_adapter('pdf').exist?(storage_key('pdf')) after call

test 'extract_text_from_pdf returns empty string when pdf key absent in adapter'
  # use a blob with no converted files; assert '' returned without error

test 'extract_text_from_pdf returns cached txt when txt key already exists in adapter'
  # pre-write a txt file to converted store; assert extract_text_from_pdf returns that content
  # verifies storage_adapter('txt').open path, not filepath
```

**Pattern B — Derivative-file existence (stubbed S3)**

```
test 'extract_text_from_pdf uses storage_adapter to check pdf/txt existence with S3'
  # stub S3 adapter exist?(pdf_key) → true, exist?(txt_key) → true, open(txt_key) → "text"
  # assert result is "text", no File.exist? called
```

---

**Pattern C — Conversion pipeline (local backend)**

```
test 'convert_to_pdf no-ops when pdf key already exists in adapter'
  # pre-write pdf to adapter; mock Libreconv to raise if called
  # assert Libreconv.convert never called

test 'convert_to_pdf converts a doc blob and writes pdf back to adapter'
  # use :doc_content_blob; assert storage_adapter('pdf').exist?(storage_key('pdf')) after call
  # this is an integration-style test — requires LibreOffice available in CI

test 'convert_to_pdf logs error and does not raise when Libreconv fails'
  # stub Libreconv.convert to raise; assert no exception propagates
  # assert Rails.logger.error called

test 'convert_to_pdf cleans up staging Tempfile even when Libreconv raises'
  # stub Libreconv.convert to raise; assert close! called on the staging Tempfile
  # verifies the ensure block

test 'extract_text_from_pdf runs Docsplit and writes txt key to adapter after pdf conversion'
  # start from a :pdf_content_blob that has been through convert_to_pdf
  # assert storage_adapter('txt').exist?(storage_key('txt')) after call

test 'with_temporary_copy_of_converted yields local path for local adapter'
  # assert block receives a real filesystem path for an existing pdf blob

test 'with_temporary_copy_of_converted yields a temp path and cleans up for S3 adapter'
  # stub S3 open(pdf_key) → StringIO with pdf content
  # assert block receives a path; assert file is removed after block
```

**Pattern C — Conversion pipeline (stubbed S3)**

```
test 'adapter_convert_to_pdf writes Libreconv output to S3 adapter'
  # stub Libreconv.convert to write a sentinel byte to pdf_tmp.path
  # stub S3 put_object; assert put_object called with correct bucket/key
  # assert storage_adapter('pdf').write called once with storage_key('pdf')
```

---

**Backward-compatibility bridge**

```
test 'convert_to_pdf called with explicit local paths uses legacy path (controller compat)'
  # call convert_to_pdf(some_local_dat_path, some_local_pdf_path)
  # assert legacy_convert_to_pdf invoked, not adapter_convert_to_pdf
  # ensures Cycle 6b does not break the controller before it is updated
```

---

**Existing tests to keep green (do not modify)**

- `test 'pdf_contents_for_search for a doc file'` — `content_blob_test.rb:607`
- `test 'pdf_contents_for_search for a pdf file'` — `content_blob_test.rb:614`

---

**Definition of done:**
- All existing `pdf_contents_for_search` tests in `content_blob_test.rb` pass unchanged.
- All new tests in `content_extraction_test.rb` pass.
- `grep` finds no `File.read(filepath`, `FileUtils.cp filepath`, or `File.exist?(filepath` remaining in `content_extraction.rb`.
- `convert_to_pdf` still accepts explicit path arguments (backward-compatible).
- `with_temporary_copy_of_converted` exists on `ContentBlob` and is tested.

**Suggested commits:**
1. `refactor: replace simple reads in ContentExtraction with data_io_object (Pattern A)`
2. `refactor: replace derivative-file checks in ContentExtraction with adapter calls (Pattern B)`
3. `feat: route PDF conversion pipeline through storage adapter with write-back (Pattern C)`

---

### Cycle 7a — Storage configuration validation and diagnostics

### Objective
Fail early on invalid storage configuration and provide a safe, explicit way to test live S3 connectivity.

### Why now
The storage backend feature is not production-ready unless misconfiguration is caught before runtime and operators have a clear way to verify connectivity.

### Scope
- Validate configuration structure at boot (no network calls)
- Provide a runtime connectivity test for S3-compatible backends
- Improve operational usability without introducing UI complexity

### Files to change
- config/initializers/seek_storage.rb
- lib/seek/storage.rb
- lib/seek/storage/s3_adapter.rb
- lib/tasks/seek_storage.rake
- config/seek_storage.yml.example
- test/unit/seek/storage_test.rb
- test/unit/seek/storage/s3_adapter_test.rb

### Implementation steps
- Add validation for required configuration keys based on selected backend
    - Validate presence of:
        - backend
        - bucket (for S3)
        - access_key_id
        - secret_access_key
        - endpoint (if required for S3-compatible providers)
    - Raise human-readable errors for missing/invalid values
    - Do not perform network calls during boot

- Introduce a clear validation boundary:
    - Configuration validation happens before adapter initialization
    - Adapter assumes config is valid

- Add `S3Adapter#test_connection`
    - Perform a read-only operation (e.g. `list_objects` with `max_keys: 1`)
    - Verify credentials, bucket access, and endpoint configuration
    - Return structured success/failure result

- Add rake task: rake seek:storage:test
- Calls `test_connection` on active adapter
- Prints clear success/failure message
- Differentiates:
    - authentication failure
    - bucket not found
    - endpoint/network errors
- Optionally exit non-zero on failure

- Add example configuration:
- `config/seek_storage.yml.example`
- Document required fields and S3-compatible options (endpoint, path style)
- Ensure real credentials are not committed

### Risks
- Boot must not depend on network availability
- Error messages must not expose secrets
- S3-compatible providers may require additional options (endpoint, path-style)
- Over-validating provider-specific settings may reduce flexibility

### Definition of done
- Invalid S3 configuration fails boot with clear, actionable error
- Valid configuration boots without contacting S3
- `rake seek:storage:test` reports success/failure clearly
- Task works against local MinIO
- Tests cover validation and connection diagnostics
- No secrets committed to repository

### Suggested commit scope
One PR:
feat: storage configuration validation and diagnostics

## Cycle 7b — Admin storage status panel (read-only)

### Objective
Provide visibility into the active storage backend and configuration status in the admin interface.

### Why now
After validation and diagnostics exist, admins benefit from a quick way to confirm which backend is active and whether configuration is valid.

### Scope
- Read-only display only
- No editing of configuration through UI

### Files to change
- app/controllers/admin_controller.rb (or relevant admin controller)
- app/views/admin/
- optional helper/service for exposing storage status

### Implementation steps
- Display:
    - active backend (local or s3)
    - bucket name (safe to display)
    - endpoint (if configured)
- Optionally show:
    - whether configuration passed validation
- Do not:
    - expose credentials
    - allow editing configuration via UI

### Risks
- Accidentally exposing sensitive configuration
- Creating expectation that config can be edited via UI

### Definition of done
- Admin page shows active storage backend clearly
- No sensitive information is exposed
- Works for both local and S3 configurations

### Suggested commit scope
One PR:
feat: admin storage backend status display


---

## Cycle 8 — Deferred migration tooling for existing local-stored blobs

### Objective
Provide an operational rake task to copy existing ContentBlob file data from local filestore to S3-compatible storage for instances that want to switch storage backends after upgrade.

### Why now
Not required for new S3-backed uploads. Only needed for existing installations migrating historical content. Implement only after storage abstraction, conversion, serving, and regression coverage are stable.

### Scope
Add a copy/migration task that:

reads existing local-backed blob files
uploads them to the configured S3 backend
verifies integrity after upload
supports safe reruns
reports success, skip, and failure outcomes
does not change active instance configuration

### Suggested task name
rake seek:storage:copy_local_to_s3

Files to change

lib/tasks/seek_storage.rake (new)
possibly a small service object if task logic becomes non-trivial

Key design requirements

dry-run mode
idempotent reruns
batch processing
structured summary output
explicit skip/error handling
source local files remain untouched
backend cutover remains a separate manual/configuration step

Decisions made

- **Migrate originals AND persisted derivatives** — both `dat` (originals via `asset_filestore_path`) and `pdf`/`txt` (derivatives via `converted_filestore_path`) are copied
- **Skip on size match, fail loudly on mismatch** — if the S3 object already exists and its byte count matches the local file size, skip silently; if sizes differ, treat as an error (do not overwrite silently)
- **`file_size` column is authoritative for originals; filesystem size for derivatives** — `ContentBlob#file_size` is used to verify original uploads; derivative size is taken from the local file at migration time

Definition of done

task successfully copies a representative test dataset from local to stubbed S3 storage
reruns are safe and skip already verified objects
failures are reported clearly without corrupting migrated objects
task does not alter configured backend or delete local files

Tests to add

copies one blob successfully
dry-run reports work without uploading
skips already migrated blob
reports missing source file
handles partial failures and continues
verifies integrity check behavior
if in scope, migrates persisted derivatives
rerun remains idempotent
---

## Suggested implementation order

1. **Cycle 1** — Tests (no risk, immediate value)
2. **Cycle 2** — LocalAdapter extraction (pure refactor, testable against Cycle 1)
3. **Cycle 3** — Storage module + config loading (no behaviour change, local default)
4. **Cycle 4** — S3Adapter (new code, fully tested with stubs, no production impact yet)
5. **Cycle 5** — Download/streaming wiring (first user-visible change for S3)
6. **Cycle 6** — Content extraction wiring (needed for full S3 functionality)
7. **Cycle 7** — Admin/ops tooling (needed before shipping to production)
8. **Cycle 8** — Migration task (deferred, ship when needed)

Each cycle 1–7 is independently reviewable and safe to merge. Cycles 1–3 are pure refactors/foundation with no behaviour change for any existing deployment.

---

## What I would explicitly defer

- **Git filestore**: complex, versioned, entirely separate concern — leave local-only for now
- **RDF filestore**: low-volume, not user-facing — easy to add in a follow-up using the same adapter interface
- **Avatar/model image storage**: managed by fleximage gem, needs its own approach
- **Encryption key files** (`attr_encrypted_key_path`, `secret_key_base_path`): must stay local filesystem for security
- **Migration of existing files**: separate task (Cycle 8), not blocking for new instances
- **Multipart upload for large files**: S3 multipart is more complex; defer until files > 5 GB are a real concern
- **CDN/CloudFront URL signing**: follow-up on top of presigned URLs if needed
- **Streaming upload to S3** (avoiding a local tmp write): optimisation, not correctness — defer

---

## Critical files to modify (summary)

| File | Cycles |
|------|--------|
| `app/models/content_blob.rb` | 2 |
| `lib/seek/content_blob_common.rb` | 5 |
| `lib/seek/content_extraction.rb` | 6 |
| `lib/seek/storage.rb` (new) | 3 |
| `lib/seek/storage/local_adapter.rb` (new) | 2, 5, 6 |
| `lib/seek/storage/s3_adapter.rb` (new) | 4, 5, 6 |
| `config/seek_storage.yml` (new) | 3 |
| `config/initializers/seek_storage.rb` (new) | 3, 7 |
| `Gemfile` | 4 |
| `lib/tasks/seek_storage.rake` (new) | 7, 8 |
| `test/unit/content_blob_test.rb` | 1 |
| `test/unit/seek/storage/` (new) | 2, 4 |

---

## Current status summary

*Last verified: 2026-04-14 against branch `s3-support`.*

### What is implemented (verified against code + passing tests)

| Cycle | Status | Evidence |
|-------|--------|----------|
| **1** — Characterise tests | ✅ Done | `test/unit/content_blob_test.rb` lines 966–1034; 11 tests, all pass |
| **2** — LocalAdapter extraction | ✅ Done | `lib/seek/storage/local_adapter.rb`; all 7 ContentBlob file I/O methods replaced; `lib/seek/data/checksums.rb` also ported (streaming digest via adapter) |
| **3** — Seek::Storage module + config | ✅ Done | `lib/seek/storage.rb`; `config/seek_storage.yml`; `test/unit/seek_storage_test.rb` (7 tests, all pass) |
| **4** — S3Adapter | ✅ Done | `lib/seek/storage/s3_adapter.rb`; `test/unit/seek/s3_adapter_test.rb` (12 tests, all pass); `aws-sdk-s3` in Gemfile with `require: false` |
| **4b** — MinIO smoke test | ✅ Done | `script/minio_smoke_test.rb` (untracked, one-off script) |
| **5** — Download/streaming wiring | ✅ Done | `serve_blob_file` helper in `lib/seek/content_blob_common.rb` routes through adapter; `handle_download` calls it; `handle_download_zip` uses `full_path \|\| make_temp_copy` for S3 fallback |
| **5b** — ContentBlob#file + csv_data | ✅ Done | `ContentBlob#file` → `storage_adapter.open(storage_key)`; `:path` removed from delegate; `ContentBlobsController#csv_data` uses `file.read.encode(...)` |
| **6** — ContentExtraction wiring | ✅ Done | `lib/seek/content_extraction.rb` fully rewritten (Patterns A/B/C); `with_temporary_copy_of_converted` added to `ContentBlob`; backward-compat `convert_to_pdf` bridge; `test/unit/seek/content_extraction_test.rb` (22 tests, all pass, incl. 4 stubbed-S3 tests) |
| **6b** — `pdf_or_convert` controller | ✅ Done | `pdf_or_convert` rewritten to use adapter (`serve_pdf` helper); `legacy_convert_to_pdf` removed; `convert_to_pdf` simplified to no-arg adapter-only call |
| **7a** — Config validation + diagnostics | ✅ Done | `Seek::Storage.validate_config!` raises at boot; `S3Adapter#test_connection`; `seek:storage:test` rake task; `config/seek_storage.yml.example`; `test/unit/seek/storage_test.rb` (9 tests); `test/unit/seek/s3_adapter_test.rb` (17 tests) |
| **7b** — Admin storage status panel | ✅ Done | `Seek::Storage.status` (credentials excluded); `app/views/admin/_storage_status.html.erb`; folding panel in admin index; 4 tests in `storage_test.rb` |
| **8** — Migration rake task | ✅ Done | `lib/seek/storage/local_to_s3_migrator.rb`; `seek:storage:copy_local_to_s3` rake task (dry-run support); copies originals + `pdf`/`txt` derivatives; idempotent; `test/unit/seek/local_to_s3_migrator_test.rb` (9 tests) |

### What should be done next

All cycles complete. Consider shipping a PR for cycles 7a + 7b + 8 together.

### Mismatches between plan and code

| # | Mismatch | Impact |
|---|----------|--------|
| 1 | **Plan header was stale** — said "Cycle 5b next" but 5b was done. Fixed above. | None |
| 2 | **Cycle 5 implementation differs from plan** — plan called for `serve_to_controller` on the adapters; code uses `serve_blob_file` helper in `content_blob_common.rb` instead. Functionally equivalent, arguably cleaner. | None |
| 3 | **Cycle 3 code snippet in plan has wrong filename** — plan block shows `config/storage.yml`; actual implementation (correctly) uses `config/seek_storage.yml`. | Confusing only — code is correct |
| 4 | **`seek_storage.yml` `development:` block is live S3 config** — currently points at `localhost:9000` MinIO. Must be reverted to `<<: *default` (local) before merging to main, or this file must be `.gitignore`d with an example template. | Risk: dev environment without MinIO running will fail on first file operation |
| 5 | **`handle_download_zip` single-file S3 path uses temp copy, not presigned redirect** — for a single blob with S3 active, the code does `make_temp_copy` (downloads file locally) then `send_file`. Works, but is inefficient for large files vs a presigned redirect. Not a correctness bug. | Minor inefficiency |
| 6 | **Cycle 6 `content_blob_common.rb` changes were already resolved** — Cycle 5's `full_path \|\| make_temp_copy` pattern means raw `File.size`/`IO.read` calls there operate on already-resolved local paths. Removed from Cycle 6 scope. | Fixed in plan |
| 7 | **`with_local_copy` on adapters removed from design** — original plan proposed adding this to both adapters. `with_temporary_copy` on ContentBlob already does this correctly and is S3-aware. Cycle 6 uses `with_temporary_copy` + `data_io_object` instead. | Fixed in plan |
| 8 | **`to_csv` / `to_spreadsheet_xml` use file path, not IO (Pattern A deviation)** — plan said "pass IO directly". SysMODB's IO path writes binary data to a text-mode `Tempfile`, causing `Encoding::UndefinedConversionError` on binary XLS/XLSX content. Fixed by adding `with_dat_path` private helper (yields real on-disk path for local, falls back to `with_temporary_copy` for S3). Functionally correct for both backends. | Documented |
| 9 | **`content_blob_test.rb:607,614` (`pdf_contents_for_search`) fail** — pre-existing failure, `pdftotext` not installed on this dev machine. Not caused by Cycle 6. New tests in `content_extraction_test.rb` stub Docsplit to be machine-independent. | Pre-existing, not a regression |
