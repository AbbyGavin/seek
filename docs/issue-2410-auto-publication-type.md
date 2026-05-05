# Issue #2410 — Automatically Set Publication Type When Querying DOI/PubMed

## Requirements

1. Fetch the resource type automatically from the API response and pre-fill the corresponding field.
2. Allow manual selection of the publication type in case the type is missing from the response.

---

## What Was Changed

### New model methods: `PublicationType.from_doi_type` / `from_pubmed_types`

`app/models/publication_type.rb`

Three static mappings were added to `PublicationType`:

- `CROSSREF_TYPE_TO_KEY` — maps Crossref API `type` strings (e.g. `"journal-article"`, `"book-chapter"`) to SEEK publication type keys.
- `DATACITE_TYPE_TO_KEY` — maps DataCite `resourceTypeGeneral` strings (e.g. `"ConferencePaper"`, `"Dataset"`) to SEEK keys.
- `PUBMED_TYPE_TO_KEY` — maps MEDLINE PT (Publication Type) field values to SEEK keys (see PubMed API section below).

`from_doi_type(doi_type)` checks both Crossref and DataCite maps and returns the matching `PublicationType`, or `nil`.

`from_pubmed_types(pub_types)` accepts an array of PT strings (a PubMed entry can have multiple), returns the first match, or falls back to `journalarticle` (PubMed indexes almost exclusively journal literature).

---

## PubMed API

SEEK fetches PubMed metadata via the NCBI EFetch API in MEDLINE text format using BioRuby (`Bio::PubMed.efetch`):

```
https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=<PMID>&rettype=medline&retmode=text&email=<configured_email>&tool=SEEK
```

Example for PMID 23865479 (a journal article):
```
https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=23865479&rettype=medline&retmode=text&email=seek@example.com&tool=SEEK


https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=6018949

https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=6018949&retmode=json 


```

The raw MEDLINE response contains a `PT` (Publication Type) field that can appear multiple times (one per type value):

```
PT  - Journal Article
PT  - Research Support, Non-U.S. Gov't
```

`Bio::MEDLINE#publication_type` collects all PT values into an array: `["Journal Article", "Research Support, Non-U.S. Gov't"]`.

### PubMed PT values → SEEK types

| PubMed PT value | SEEK type |
|---|---|
| Journal Article | journalarticle |
| Review | journalarticle |
| Systematic Review | journalarticle |
| Meta-Analysis | journalarticle |
| Clinical Trial / Randomized Controlled Trial | journalarticle |
| Case Reports, Letter, Editorial, Comment, News, Biography | journalarticle |
| Historical Article, Retraction of Publication | journalarticle |
| Preprint | preprint |
| Dataset | dataset |
| Software | software |
| Book | book |
| Book Chapter | bookchapter |
| Congress | conferenceproceeding |
| Technical Report / Guideline / Government Document | report |
| *(anything else)* | journalarticle (fallback) |

Full PubMed publication type list: https://www.nlm.nih.gov/mesh/pubtypes.html

### Why `Bio::Reference` doesn't carry type

`Bio::MEDLINE#reference` builds a `Bio::Reference` hash from selected fields but does **not** include `PT`. The MEDLINE object must be retained before calling `.reference` to extract the type — which is what the fix in `fetch_pubmed_or_doi_result` does.

---

### Auto-detect in `extract_doi_metadata`

`app/models/publication.rb`

After extracting all DOI metadata fields, `extract_doi_metadata` now calls `PublicationType.from_doi_type(doi_record.type)` and assigns the result to `self.publication_type` when a mapping is found.

### Controller: `fetch_preview` no longer requires pre-selection

`app/controllers/publications_controller.rb`

Previously the action returned an error if `publication_type_id` was blank. That guard was removed. After fetching metadata, it sets `@publication_type_missing = @publication.publication_type.nil?` so the view can show a warning when auto-detection failed.

### View: warning banner + optional dropdown

`app/views/publications/new.html.erb`

- The publication type dropdown placeholder was changed to `"Auto-detect from DOI (optional)"` to communicate the new behaviour.
- A hidden warning div `#publication_type_warning` was added. It becomes visible (via JS) when the API response contained no recognisable type.
- `SEEK_PUB_TYPE_KEY_TO_ID` — a JSON map of `key → database id` for all publication types is inlined as a JS variable, used by client-side auto-fill.
- A `change` handler on `#Register #publication_publication_type_id` syncs manual selection into the hidden preview field and hides the warning.

### JS: client-side type pre-fill

`app/assets/javascripts/publications.js`

- `CROSSREF_TYPE_TO_PUB_KEY` — mirrors the server-side Crossref mapping for the client-side Crossref fetch path.
- `setPubTypeInCreateTab(key)` — sets the `#Create` tab dropdown using `SEEK_PUB_TYPE_KEY_TO_ID`.
- Called after a successful Crossref API response with the mapped type key.
- For the PubMed path, `journalarticle` is hardcoded (PubMed is a biomedical literature database; all results are journal articles).

### Server-side JS response: `fetch_preview.js.erb`

Sets `#Register #publication_publication_type_id` to the server-detected id. Shows or hides `#publication_type_warning` based on `@publication_type_missing`.

### Crash fix in preview partial

`app/views/publications/_publication_preview.html.erb`

Replaced `PublicationType.find(publication.publication_type_id)` (crashes when `publication_type_id` is nil) with `publication.publication_type&.title` (safe navigation).

---

## Test Coverage Added

| Test | Location |
|---|---|
| `fetch_preview` succeeds without a pre-selected type | `publications_controller_test.rb` |
| `fetch_preview` hides warning when type is detected | `publications_controller_test.rb` |
| `extract_doi_metadata` sets type from `"journal-article"` | `publication_test.rb` |
| `extract_doi_metadata` leaves type nil when API type is blank | `publication_test.rb` |

---

## Issues Found / Suggested Improvements

### 1. ~~PubMed server-side path never sets `publication_type`~~ ✅ Fixed

**Was:** `extract_pubmed_metadata` did not set `publication_type`. When `fetch_preview` was called with `protocol=pubmed`, `@publication.publication_type` was always `nil`, causing `@publication_type_missing` to be `true` — the warning would appear on every PubMed fetch even though the client-side JS hardcoded `journalarticle`.

**Fix applied:**
- `fetch_pubmed_or_doi_result` now retains the `Bio::MEDLINE` object long enough to read `publication_type` (the PT field array) before converting it to `Bio::Reference`.
- `PublicationType::PUBMED_TYPE_TO_KEY` maps all significant MEDLINE PT values to SEEK keys, with `journalarticle` as fallback.
- `PublicationType.from_pubmed_types(pub_types)` selects the first matching key from the array.
- `extract_pubmed_metadata` calls `from_pubmed_types` and assigns the result.

### 2. ~~Duplicate Crossref type mapping (JS vs Ruby)~~ ✅ Fixed

**Was:** `CROSSREF_TYPE_TO_PUB_KEY` in `publications.js` was a static copy of `PublicationType::CROSSREF_TYPE_TO_KEY`. Adding a new Crossref type required editing both files.

**Fix applied:** The static object was removed from `publications.js`. `new.html.erb` now inlines the mapping from the Ruby constant at render time, alongside `SEEK_PUB_TYPE_KEY_TO_ID`:
```erb
var CROSSREF_TYPE_TO_PUB_KEY = <%= PublicationType::CROSSREF_TYPE_TO_KEY.to_json.html_safe %>;
```
Future additions to `CROSSREF_TYPE_TO_KEY` are automatically reflected on the client.

### 3. ~~Missing test: warning shown when type is undetectable~~ ✅ Fixed

**Was:** No test for the case where the DOI response has an unrecognised type and the warning should appear.

**Fix applied:** Added `test 'fetch_preview shows warning when publication type cannot be detected'` in `publications_controller_test.rb`, backed by a new VCR cassette `test/vcr_cassettes/doi/doi_crossref_unknown_type_response_1.yml` that returns a Crossref response with `"type":"peer-review"` (a real Crossref type not in the mapping). The test asserts `assert_response :success` and `assert_match(/publication_type_warning.*show/, response.body)`.

### 4. ~~Two nearly identical controller tests~~ ✅ Fixed

**Was:** `should fetch doi preview without pre-selecting publication type` and `fetch_preview auto-detects publication type and hides warning` made the same request; the first only checked `assert_response :success`.

**Fix applied:** Merged into a single test `fetch_preview auto-detects publication type without pre-selection and hides warning` that asserts both `success` and the `hide` behaviour.

### 5. ~~Missing newline at end of two files~~ ✅ Fixed

**Was:** `app/views/publications/fetch_preview.js.erb` and `app/views/publications/new.html.erb` both lacked a trailing newline.

**Fix applied:** Trailing newlines added to both files.

### 6. ~~No hard server-side guard before final save~~ ✅ Already present

`app/models/publication.rb` already has `validates :publication_type, presence: true, on: :create` (line 75). No change needed.

---

## Overall Assessment

Both requirements are fulfilled:

- **Auto-detection** works for DOI (Crossref and DataCite) and PubMed, both server-side and client-side.
- **Manual fallback** is available — the dropdown is still shown and the warning guides users when detection fails.

All identified issues are resolved. Ready to merge.
