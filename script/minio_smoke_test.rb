#!/usr/bin/env ruby
# Smoke test for Seek::Storage::S3Adapter against a live MinIO server.
#
# Prerequisites:
#   docker run -p 9000:9000 -p 9001:9001 \
#     -e MINIO_ROOT_USER=seek -e MINIO_ROOT_PASSWORD=seek1234 \
#     -v minio-seek-data:/data \
#     quay.io/minio/minio server /data --console-address ":9001"
#
# Run:
#   bundle exec ruby script/minio_smoke_test.rb

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'aws-sdk-s3'
require 'seek/storage/s3_adapter'
require 'tempfile'

BUCKET   = 'seek-smoke-test'
ENDPOINT = 'http://localhost:9000'
REGION   = 'us-east-1'
USER     = 'seek'
PASS     = 'seek1234'

# The adapter uses prefix/key → object key is "smoke/test.dat" etc.
adapter = Seek::Storage::S3Adapter.new(
  bucket:            BUCKET,
  prefix:            'smoke',
  region:            REGION,
  access_key_id:     USER,
  secret_access_key: PASS,
  endpoint:          ENDPOINT,
  force_path_style:  true
)

# Raw client just for bucket lifecycle (not part of adapter interface)
raw_client = Aws::S3::Client.new(
  region: REGION, access_key_id: USER, secret_access_key: PASS,
  endpoint: ENDPOINT, force_path_style: true
)

# ── setup ───────────────────────────────────────────────────────────────────
puts "\nSetting up bucket '#{BUCKET}' on #{ENDPOINT} ..."
begin
  raw_client.create_bucket(bucket: BUCKET)
  puts "  Bucket created."
rescue Aws::S3::Errors::BucketAlreadyOwnedByYou
  puts "  Bucket already exists — continuing."
rescue => e
  abort "  FATAL: could not create bucket: #{e.message}"
end

# ── helpers ──────────────────────────────────────────────────────────────────
passed = 0
failed = 0

def check(label, actual, expected = true)
  if actual == expected
    puts "  PASS  #{label}"
    passed += 1
  else
    puts "  FAIL  #{label}  (got #{actual.inspect}, expected #{expected.inspect})"
    failed += 1
  end
rescue => e
  puts "  FAIL  #{label}  (raised #{e.class}: #{e.message})"
  failed += 1
end

# Reopen as closures so passed/failed are shared
passed = 0
failed = 0
results = []

def run_check(label)
  result = yield
  puts "  PASS  #{label}"
  result
rescue => e
  puts "  FAIL  #{label}  — #{e.class}: #{e.message}"
  nil
end

checks_passed = 0
checks_failed = 0

def assert_check(label, actual, expected)
  if actual == expected
    puts "  PASS  #{label}"
    true
  else
    puts "  FAIL  #{label}  (got #{actual.inspect}, expected #{expected.inspect})"
    false
  end
end

# ── tests ────────────────────────────────────────────────────────────────────
puts "\nRunning smoke checks ...\n\n"

content  = "Hello from SEEK S3Adapter smoke test — #{Time.now}"
key1     = 'test.dat'
key2     = 'copy.dat'
missing  = 'does-not-exist.dat'

all_pass = true

# 1. write String
begin
  adapter.write(key1, content)
  puts "  PASS  write(String)"
rescue => e
  puts "  FAIL  write(String) — #{e.message}"; all_pass = false
end

# 2. exist? true after write
begin
  result = adapter.exist?(key1)
  result ? puts("  PASS  exist? → true after write") : (puts("  FAIL  exist? → expected true"); all_pass = false)
rescue => e
  puts "  FAIL  exist? — #{e.message}"; all_pass = false
end

# 3. size
begin
  sz = adapter.size(key1)
  sz == content.bytesize ? puts("  PASS  size → #{sz} bytes") : (puts("  FAIL  size → got #{sz}, expected #{content.bytesize}"); all_pass = false)
rescue => e
  puts "  FAIL  size — #{e.message}"; all_pass = false
end

# 4. open + read
begin
  io = adapter.open(key1)
  body = io.read
  body == content ? puts("  PASS  open → content matches") : (puts("  FAIL  open → content mismatch"); all_pass = false)
rescue => e
  puts "  FAIL  open — #{e.message}"; all_pass = false
end

# 5. copy_from_path
begin
  Tempfile.create(['seek_smoke', '.dat']) do |f|
    f.write('copy from local file')
    f.flush
    adapter.copy_from_path(f.path, key2)
  end
  puts "  PASS  copy_from_path"
rescue => e
  puts "  FAIL  copy_from_path — #{e.message}"; all_pass = false
end

# 6. exist? true for copy
begin
  result = adapter.exist?(key2)
  result ? puts("  PASS  exist? → true for copied key") : (puts("  FAIL  exist? → expected true for copy"); all_pass = false)
rescue => e
  puts "  FAIL  exist? (copy) — #{e.message}"; all_pass = false
end

# 7. exist? false for missing key
begin
  result = adapter.exist?(missing)
  !result ? puts("  PASS  exist? → false for missing key") : (puts("  FAIL  exist? → expected false for missing key"); all_pass = false)
rescue => e
  puts "  FAIL  exist? (missing) — #{e.message}"; all_pass = false
end

# 8. delete
begin
  adapter.delete(key1)
  puts "  PASS  delete"
rescue => e
  puts "  FAIL  delete — #{e.message}"; all_pass = false
end

# 9. exist? false after delete
begin
  result = adapter.exist?(key1)
  !result ? puts("  PASS  exist? → false after delete") : (puts("  FAIL  exist? → expected false after delete"); all_pass = false)
rescue => e
  puts "  FAIL  exist? (after delete) — #{e.message}"; all_pass = false
end

# 10. presigned_url
begin
  url = adapter.presigned_url(key2, expires_in: 60)
  url.is_a?(String) && url.include?('smoke') ?
    puts("  PASS  presigned_url → #{url[0, 80]}...") :
    (puts("  FAIL  presigned_url → unexpected: #{url}"); all_pass = false)
rescue => e
  puts "  FAIL  presigned_url — #{e.message}"; all_pass = false
end

# ── cleanup ──────────────────────────────────────────────────────────────────
puts "\nCleaning up ..."
begin
  adapter.delete(key2)
  raw_client.delete_bucket(bucket: BUCKET)
  puts "  Bucket deleted.\n\n"
rescue => e
  puts "  Warning: cleanup error — #{e.message}\n\n"
end

# ── summary ──────────────────────────────────────────────────────────────────
if all_pass
  puts "All smoke checks passed."
else
  puts "One or more smoke checks FAILED — review output above."
  exit 1
end
