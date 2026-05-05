# Claude Code Plan Prompt
## SEEK Extended Metadata + HealthDCAT-AP RDF Export

---

## What This Task Is

SEEK already exports research assets as RDF using the JERM ontology and partial Dublin Core/FOAF properties. The goal here is to enrich that RDF export so that datasets with **health-domain extended metadata** (e.g. disease category, population coverage, GDPR legal basis, personal data flag) also emit **HealthDCAT-AP** terms alongside the existing JERM triples.

Concretely:
- A `DataFile` with health-domain extended metadata should, when its RDF is fetched, emit `dcat:Dataset` as a type and HealthDCAT-AP properties like `healthdcatap:healthCategory`, `healthdcatap:populationCoverage`, `dpv:hasPersonalData`, etc., in addition to the existing JERM triples.
- Resources *without* health metadata should produce unchanged output.
- The implementation must be backwards-compatible — existing DCAT/DCAT-AP consumers must keep working.

This is **not** a greenfield RDF exporter. The existing infrastructure handles graph construction, serialization, and controller routing. Most changes are additive: new vocabulary files, new columns on `extended_metadata_attributes`, and an enhanced emitter that understands value types and IRI values in addition to the current plain-literal-only behaviour.

---

## Background Knowledge You Need

### ISA Framework
SEEK organises research around **Investigation → Study → Assay**, with assets (DataFile, Model, SOP, Workflow, etc.) attached to Assays. All assets live in Projects, which belong to Institutions. Understanding this hierarchy is essential because RDF is generated per-resource and links across this hierarchy.

### SEEK Extended Metadata System
Extended metadata allows attaching arbitrary structured fields to any asset without changing the core schema. Three AR models:
- `ExtendedMetadataType` — a named schema (e.g. "HealthDCAT-AP v1.0") with a `supported_type` (the class it can attach to) and a list of attributes.
- `ExtendedMetadataAttribute` — one field definition inside a type. Has: `title`, `pos`, `required`, `pid` (a URI string used as the RDF predicate), `sample_attribute_type` (controls the data type and UI widget), and optionally `linked_extended_metadata_type` for nested schemas.
- `ExtendedMetadata` — one instance of an `ExtendedMetadataType`, attached polymorphically to an asset via `item_type`/`item_id`. The actual values are stored as JSON in a `json_metadata` text column and accessed via `get_attribute_value(attribute)`.

The `pid` column on `ExtendedMetadataAttribute` is the hook the plan needs. It already carries a predicate URI. The existing `extended_metadata_triples` method in `RdfGeneration` already reads `pid` and emits triples — but only as plain `RDF::Literal` (no typed literals, no IRI values, no language tags).

### SEEK RDF Generation
`Seek::Rdf::RdfGeneration` is a **module** (mixin), not a class. It is `include`d directly in model classes like `DataFile`, `Assay`, `Study`, etc. The key methods:
- `to_rdf_graph` — assembles an `RDF::Graph` from four steps: `describe_type` (emits the JERM type triple), `generate_from_csv_definitions` (reads `rdf_mappings.csv`), `additional_triples` (model-specific extras), `extended_metadata_triples` (the `pid`-based emitter).
- `to_rdf` — serialises the graph to **Turtle** using `RDF::Writer.for(:ttl)`.
- `to_json_ld` — already implemented, produces JSON-LD via the `json-ld` gem.
- `ns_prefixes` — returns the hash of prefix → URI passed to the Turtle writer. Currently includes `jerm`, `dcterms`, `owl`, `foaf`, `sioc`, `mixs`, `uniprot`, `fairbd`, `xsd`. **No `dcat:` or `healthdcatap:` prefix yet.**

### What "`:rdf` MIME type" Means in SEEK
The Rails MIME registration is:
```ruby
Mime::Type.register "text/turtle", :rdf, ["application/rdf", "application/x-turtle"]
```
So the `:rdf` format handler serves **Turtle**, not RDF/XML. `format.rdf { render template: 'rdf/show' }` renders `app/views/rdf/show.rdf.erb`, which calls `asset_rdf` helper → `resource_for_controller.to_rdf` → Turtle string.

There is a `:jsonld` MIME type registered separately (`application/ld+json`). There is **no** `:rdfxml` format currently registered.

### RDF vocabulary layers
- **JERM** (`http://jermontology.org/ontology/JERMOntology#`) — SEEK's own ontology; types like `jerm:Data`, `jerm:Assay`; predicates like `jerm:hasCreator`, `jerm:isPartOf`.
- **Dublin Core Elements** (`RDF::Vocab::DC`, prefix `dc:`, URI `http://purl.org/dc/elements/1.1/`) — used in the CSV mappings for `dc:title`, `dc:description`, `dc:created`, `dc:modified`.
- **Dublin Core Terms** (`RDF::Vocab::DCTERMS`, prefix `dcterms:`, URI `http://purl.org/dc/terms/`) — the *modern* vocabulary required by DCAT-AP. **Different from `RDF::Vocab::DC`.** The plan's alias `DCT = RDF::Vocab::DC` is wrong — use `RDF::Vocab::DCTERMS`.
- **DCAT** (`RDF::Vocab::DCAT`, URI `http://www.w3.org/ns/dcat#`) — not currently used in SEEK at all.
- **HealthDCAT-AP** — an extension profile of DCAT-AP. No gem support yet; must be defined manually via `RDF::Vocabulary.new(...)`.

### Gem versions (from Gemfile.lock)
| Gem | Version |
|---|---|
| `linkeddata` | 3.3.3 (umbrella gem, includes rdf-turtle, rdf-vocab, json-ld, etc.) |
| `rdf-vocab` | 3.3.2 |
| `rdf-turtle` | 3.3.1 |
| `json-ld` | 3.3.2 |
| `rdf-virtuoso` | (present, for Virtuoso triple store) |

`rdf-xml` is NOT listed separately — it may or may not be bundled by `linkeddata`. Verify before using `RDF::RDFXML::Writer`.

---

## Relevant SEEK Code

### Core RDF pipeline
| File | Role |
|---|---|
| `lib/seek/rdf/rdf_generation.rb` | Main mixin — `to_rdf_graph`, `to_rdf`, `to_json_ld`, `extended_metadata_triples`, `ns_prefixes` |
| `lib/seek/rdf/jerm_vocab.rb` | `JERMVocab` — JERM vocabulary + `defined_types` hash (drives `rdf_capable_types`) |
| `lib/seek/rdf/csv_mappings_handling.rb` | `generate_from_csv_definitions` — reads `rdf_mappings.csv` and emits triples |
| `lib/seek/rdf/rdf_mappings.csv` | Mapping table: class, method, RDF property, literal/URI flag, transform |
| `lib/seek/rdf/rdf_file_storage.rb` | Writes RDF to `tmp/filestore/rdf/` (public/private) |
| `lib/seek/rdf/rdf_repository.rb` | Pushes to Virtuoso triple store |
| `app/views/rdf/show.rdf.erb` | Template: `<%= asset_rdf.html_safe -%>` |
| `app/helpers/rdf_helper.rb` | `asset_rdf` helper → `resource_for_controller.to_rdf` |
| `lib/seek/assets_standard_controller_actions.rb:20` | `format.rdf { render template: 'rdf/show' }` — the controller hook |
| `config/initializers/mime_types.rb:10` | `:rdf` registered as `text/turtle` |
| `config/initializers/seek_rdf.rb` | Requires `rdf/rdfxml` and `rdf/vocab` |

### Extended metadata
| File | Role |
|---|---|
| `app/models/extended_metadata_attribute.rb` | One field definition; has `pid` (predicate URI string) |
| `app/models/extended_metadata_type.rb` | Named schema; links to attributes |
| `app/models/extended_metadata.rb` | One instance of a type on an asset; `get_attribute_value` reads JSON |
| `app/models/concerns/has_extended_metadata.rb` | Concern included in assets that support extended metadata |
| `db/schema.rb` (table `extended_metadata_attributes`) | Columns: `title`, `pid`, `required`, `pos`, `description`, `label`, `sample_attribute_type_id`, `sample_controlled_vocab_id`, `linked_extended_metadata_type_id`, `allow_cv_free_text` |

### Tests
| File | Role |
|---|---|
| `test/unit/rdf_generation_test.rb` | Unit tests for `to_rdf`, `to_rdf_graph`, file storage |
| `test/integration/rdf_response_test.rb` | HTTP-level test: checks MIME type and statement counts |
| `test/integration/rdf_triple_store_test.rb` | Virtuoso-related tests |
| `test/rdf_test_cases.rb` | Shared test case helpers |

### rdf_capable_types registration
`Seek::Util.rdf_capable_types` returns `JERMVocab.defined_types.keys` — so RDF support is gated by having an entry in `JERMVocab.defined_types`. Any new type that should support HealthDCAT output should already be in this list.

---

## Context for Claude Code

You are working on the [SEEK](https://github.com/seek4science/seek) research data management platform — a Ruby on Rails application. SEEK manages scientific research assets (Investigations, Studies, Assays, DataFiles, Models, Documents, People, Projects) and already exports them as RDF using the JERM ontology, Dublin Core, FOAF, and a partial DCAT mapping (see prior work: Löbe et al. 2021).

**Your task**: Design and implement an extension of SEEK's RDF export that:

1. Uses SEEK's **extended metadata** system as the source of rich, domain-specific metadata
2. Maps those fields to **HealthDCAT-AP** properties where possible, falling back to DCAT-AP / DCTERMS / FOAF / SKOS / PROV
3. Defines a minimal **`seekh:` extension namespace** only for concepts that genuinely have no standard mapping
4. Produces enriched **Turtle** output (primary, matching SEEK's existing `:rdf` format), with JSON-LD as a secondary format
5. Is **backwards-compatible** — existing DCAT/DCAT-AP consumers must continue to work unchanged

---

## Repository Orientation — Read These First

Before writing any code, explore the repository to understand the existing architecture:

```bash
# Entry points for RDF serialization
find . -name "*.rb" | xargs grep -l "RDF::" | grep -v test | grep -v spec
find . -name "*.csv" | xargs grep -l "dcat\|DCAT\|dcterms" 2>/dev/null
find . -path "*/rdf*" -name "*.rb" | grep -v test
find . -name "*.rb" | xargs grep -l "serialize.*rdf\|rdf.*serial" 2>/dev/null

# Extended metadata system
find . -name "*.rb" | xargs grep -l "ExtendedMetadata\|extended_metadata" | grep -v test
find . -path "*/models/extended*" -name "*.rb"
find . -path "*/models/sample*" -name "*.rb"

# Existing RDF vocab usage
grep -r "RDF::Vocab\|DCAT\|DCTERMS\|FOAF\|PROV" app/ lib/ --include="*.rb" -l
grep -r "RDF::Vocab::DCAT" app/ lib/ --include="*.rb"

# CSV mapping files referenced in Löbe et al.
find . -name "*.csv" | xargs grep -l "rdf\|RDF" 2>/dev/null
ls lib/seek/rdf* 2>/dev/null || find lib/ -name "*rdf*"
```

Read the following files fully before planning implementation:
- `lib/seek/rdf/rdf_generation.rb` — the main mixin; understand `to_rdf_graph`, `extended_metadata_triples`, `ns_prefixes`
- `lib/seek/rdf/rdf_mappings.csv` — the CSV-driven mapping table
- `lib/seek/rdf/jerm_vocab.rb` — the JERM vocabulary definition
- `app/models/extended_metadata_attribute.rb` and related models
- `config/initializers/mime_types.rb` — note that `:rdf` is `text/turtle`, not `application/rdf+xml`
- `Gemfile.lock` — confirm `linkeddata 3.3.3`, `rdf-vocab 3.3.2`, `rdf-turtle 3.3.1`, `json-ld 3.3.2`

---

## Namespace & Vocabulary Declarations

Establish these at the top of any RDF generation code:

```ruby
# Standard vocabularies already in rdf-vocab gem
DCAT    = RDF::Vocab::DCAT
# IMPORTANT — rdf-vocab 3.3.2 (installed version) naming:
#   RDF::Vocab::DC   = http://purl.org/dc/terms/  (Dublin Core TERMS — what we want for DCAT-AP)
#   RDF::Vocab::DC11 = http://purl.org/dc/elements/1.1/ (DC Elements 1.1)
#   RDF::Vocab::DCTERMS does NOT exist in this version (raises NameError)
# Use DC as the DCTERMS alias throughout.
DCTERMS = RDF::Vocab::DC       # http://purl.org/dc/terms/
DC11    = RDF::Vocab::DC11     # http://purl.org/dc/elements/1.1/ — only if DC Elements explicitly needed
FOAF    = RDF::Vocab::FOAF
PROV    = RDF::Vocab::PROV
SKOS    = RDF::Vocab::SKOS
VCARD   = RDF::Vocab::VCARD
XSD     = RDF::Vocab::XSD

# HealthDCAT-AP Release 6 — define manually (not in rdf-vocab gem)
# Canonical namespace: http://healthdataportal.eu/ns/health#  prefix: healthdcatap
# Spec: https://healthdataeu.pages.code.europa.eu/healthdcat-ap/releases/release-6/
HDCAT   = RDF::Vocabulary.new("http://healthdataportal.eu/ns/health#")

# SEEK extension namespace — minimal, only for genuine gaps
SEEKH   = RDF::Vocabulary.new("https://seek4science.org/vocab/seekh#")

# JERM (existing SEEK ontology — keep for backwards compatibility)
JERM    = RDF::Vocabulary.new("http://jermontology.org/ontology/JERMOntology#")
```

> **Vocabulary note — verified against installed gem (rdf-vocab 3.3.2)**: `rdf_mappings.csv` uses `RDF::Vocab::DC.created`, `RDF::Vocab::DC.title`, etc. In rdf-vocab 3.3.2 this resolves to `http://purl.org/dc/terms/` URIs — these are **already DCTERMS**, not DC Elements 1.1. The `ns_prefixes` method already labels this `'dcterms'` and points to the correct URI. `RDF::Vocab::DC11` is the DC Elements 1.1 vocabulary. New DCAT-AP code should use `RDF::Vocab::DC` (aliased as `DCTERMS` above) consistently.

---

## Target Mapping Table

This is the authoritative mapping you must implement. Implement each row as a discrete, testable unit.

### Core SEEK assets → DCAT classes

| SEEK entity | RDF class | Notes |
|---|---|---|
| `DataFile` / `Assay` | `dcat:Dataset` | Primary mapping |
| `DataFile` (downloadable) | `dcat:Distribution` | Nested under Dataset |
| `Investigation` / `Study` | `dcat:Resource` | Broader container |
| `Project` | `foaf:Project` | Existing |
| `Person` | `foaf:Person` + `vcard:Individual` | Add vcard for contact |
| `Institution` | `foaf:Organization` + `vcard:Organization` | |
| Repository root | `dcat:Catalog` | |
| External data service | `dcat:DataService` | e.g. i2b2 |

### Extended metadata fields → RDF properties

| Concept | Target property | Vocab | Value type |
|---|---|---|---|
| Dataset title | `dct:title` | DCTERMS | `xsd:string` (lang-tagged) |
| Description | `dct:description` | DCTERMS | `xsd:string` (lang-tagged) |
| Keywords | `dcat:keyword` | DCAT | `xsd:string` (repeatable) |
| Theme / category | `dcat:theme` | DCAT | IRI (controlled vocab) |
| Health category | `healthdcatap:healthCategory` | HealthDCAT-AP | IRI (`skos:Concept` from health-categories authority table) |
| Health theme | `healthdcatap:healthTheme` | HealthDCAT-AP | IRI (`skos:Concept` from health-theme authority table) |
| Health data access body | `healthdcatap:hdab` | HealthDCAT-AP | `foaf:Agent` blank node with `cv:contactPoint` |
| Population coverage | `healthdcatap:populationCoverage` | HealthDCAT-AP | Lang-tagged literal |
| Min typical age | `healthdcatap:minTypicalAge` | HealthDCAT-AP | `xsd:integer` |
| Max typical age | `healthdcatap:maxTypicalAge` | HealthDCAT-AP | `xsd:integer` |
| Number of individuals | `healthdcatap:numberOfUniqueIndividuals` | HealthDCAT-AP | `xsd:nonNegativeInteger` |
| Number of records | `healthdcatap:numberOfRecords` | HealthDCAT-AP | `xsd:nonNegativeInteger` |
| Coding system | `healthdcatap:hasCodingSystem` | HealthDCAT-AP | IRI of `dct:Standard` (Wikidata ICD-10/SNOMED entry) |
| Code values | `healthdcatap:hasCodeValues` | HealthDCAT-AP | Lang-tagged literal (e.g. `"U07.1"@en`) |
| Analytics distribution | `healthdcatap:analytics` | HealthDCAT-AP | `dcat:Distribution` blank node (technical report/CSV) |
| Publisher note | `healthdcatap:publisherNote` | HealthDCAT-AP | Lang-tagged literal |
| Publisher type | `healthdcatap:publisherType` | HealthDCAT-AP | IRI from publisher-type authority table |
| Trusted data holder | `healthdcatap:trusteddataholder` | HealthDCAT-AP | `xsd:boolean` |
| Retention period | `healthdcatap:retentionPeriod` | HealthDCAT-AP | `dct:PeriodOfTime` blank node (`dcat:startDate` / `dcat:endDate`) |
| Personal data categories | `dpv:hasPersonalData` | W3C DPV | IRI from `dpv-pd:` namespace — **not** a `healthdcatap:` property |
| GDPR legal basis | `dpv:hasLegalBasis` | W3C DPV | `dpv:LegalBasis` blank node with `dct:description` + `dct:source` |
| Processing purpose | `dpv:hasPurpose` | W3C DPV | `dpv:Purpose` blank node with `dct:description` |
| Contact point | `dcat:contactPoint` | DCAT | `vcard:Kind` blank node |
| License | `dct:license` | DCTERMS | IRI |
| Access rights | `dct:accessRights` | DCTERMS | IRI or literal |
| Publisher | `dct:publisher` | DCTERMS | `foaf:Agent` IRI |
| Creator | `dct:creator` | DCTERMS | `foaf:Agent` IRI |
| Issue date | `dct:issued` | DCTERMS | `xsd:date` |
| Modified date | `dct:modified` | DCTERMS | `xsd:dateTime` |
| Temporal coverage | `dct:temporal` | DCTERMS | `dct:PeriodOfTime` |
| Spatial coverage | `dct:spatial` | DCTERMS | IRI (gazetteer/GeoNames) |
| Provenance | `dct:provenance` | DCTERMS | Literal or IRI |
| Was attributed to | `prov:wasAttributedTo` | PROV | IRI |
| Was generated by | `prov:wasGeneratedBy` | PROV | IRI |
| Language | `dct:language` | DCTERMS | IRI (ISO 639) |
| Format / media type | `dct:format` + `dcat:mediaType` | DCTERMS/DCAT | IRI (IANA) |
| Byte size | `dcat:byteSize` | DCAT | `xsd:decimal` |
| Download URL | `dcat:downloadURL` | DCAT | IRI |
| Access URL | `dcat:accessURL` | DCAT | IRI |
| Version | `dcat:version` | DCAT | `xsd:string` |
| Related resource | `dct:relation` | DCTERMS | IRI |
| Conforms to | `dct:conformsTo` | DCTERMS | IRI (standard/profile) |
| SEEK-specific field (no match) | `seekh:*` | SEEK extension | defined per field |

---

## Implementation Plan — Ordered Cycles

| Cycle | Status | Notes |
|---|---|---|
| 0 | ✅ Done | Audit + docs |
| 1 | ✅ Done | HDCATVocab, SEEKHVocab, ns_prefixes |
| 2 | ✅ Done | `rdf_value_type`/`rdf_datatype` on `sample_attribute_types`; `RdfMapping` value object |
| 3 | ✅ Done | ExtendedMetadataEmitter + sample_metadata_triples upgrade |
| 4 | ✅ Done | DCAT type assertions + dcat:Distribution |
| 5 | ✅ Done | Blank node support in ExtendedMetadataEmitter + DPV vocabulary |
| 6 | ✅ Done | Serialization and format wiring |
| 7 | ✅ Done | SHACL validation shapes |
| 8 | ✅ Done | Seed data & example output |
| 9 | ✅ Done | Application profile documentation |
| 9.5 | ✅ Done | `/dcat` endpoint — resolves two-JSON-LD-pipeline ambiguity |
| 10 | ✅ Done | Regression & backwards-compat tests |

---

### Cycle 0: Repository audit & environment setup ✅

**Goal**: Understand the existing code before writing a single line.

Tasks:
1. Map the complete call chain from a controller action (e.g. `GET /data_files/1` with `Accept: text/turtle`) down to the RDF graph construction and serialization. Key path: `AssetsStandardControllerActions#show` → `format.rdf { render template: 'rdf/show' }` → `app/views/rdf/show.rdf.erb` → `asset_rdf` helper → `resource.to_rdf` → `to_rdf_graph` → graph built via four methods.
2. Identify all files that will need modification (list them explicitly)
3. Confirm gem versions for `rdf-vocab`, `rdf-turtle`, `json-ld`, `linkeddata` from `Gemfile.lock`
4. Document how extended metadata types and instances are stored — the `pid` column on `extended_metadata_attributes` is the predicate URI hook; `get_attribute_value` on an `ExtendedMetadata` instance retrieves the value as a Ruby object
5. Identify existing tests for the RDF serializer — list test file paths
6. Output a plain-text architecture summary: current state, planned changes, files to create/modify

**Deliverable**: `docs/healthdcat_rdf_audit.md` — architecture notes, file list, gem version table

---

### Cycle 1: Vocabulary definitions & namespace registration ✅

**Goal**: Add the `seekh:` and `healthdcatap:` namespaces cleanly to SEEK's RDF infrastructure.

Tasks:
1. Create `lib/seek/rdf/vocabularies/health_dcat.rb` — defines `HDCAT` vocabulary with all HealthDCAT-AP properties used in the mapping table above (use `RDF::Vocabulary.new` with `property` declarations)
2. Create `lib/seek/rdf/vocabularies/seek_health.rb` — defines `SEEKH` namespace for extension terms
3. Register both namespaces in `ns_prefixes` in `lib/seek/rdf/rdf_generation.rb`. Also add `dcat` and `dcterms` (note: the existing `dcterms` prefix in `ns_prefixes` points to `RDF::Vocab::DC`, i.e. DC11 — check whether this is intentional or a bug before changing it)
4. Require the new vocabulary files from `config/initializers/seek_rdf.rb`
5. Write unit tests confirming that `HDCATVocab.healthCategory`, `HDCATVocab.retentionPeriod`, `SEEKHVocab[:someExtendedField]` etc. resolve to correct IRIs (see `test/unit/rdf/vocabularies_test.rb` — already done)

**Files to create**:
- `lib/seek/rdf/vocabularies/health_dcat.rb`
- `lib/seek/rdf/vocabularies/seek_health.rb`
- `test/unit/rdf/vocabularies_test.rb` (or add to `test/unit/rdf_generation_test.rb`)

---

### Cycle 2: RDF mapping configuration — columns on `SampleAttributeType` ✅

**Goal**: Allow each metadata field to declare its RDF value type and datatype. Place the columns on `sample_attribute_types` — the existing shared type layer — so that both `ExtendedMetadataAttribute` and `SampleAttribute` inherit RDF configuration automatically through the `belongs_to :sample_attribute_type` association that both models already share via `Seek::JSONMetadata::Attribute`.

> **Architecture decision (revised after investigation)**: The initial plan added `rdf_value_type`/`rdf_datatype` directly to `extended_metadata_attributes`. After auditing the codebase, the correct layer is `sample_attribute_types`:
>
> - `SampleAttributeType` already has `has_many :extended_metadata_attributes` and `has_many :sample_attributes`.
> - The shared concern `Seek::JSONMetadata::Attribute` already delegates type-level behaviour (`controlled_vocab?`, `seek_sample?`, etc.) to `sample_attribute_type`. RDF serialization is the same category.
> - `SampleAttributeType` instances are NOT global singletons — 13 String types and a dedicated "URI" type (with URI-validating regexp) already exist, so per-use specialisation is the established norm.
> - `SampleAttribute` also has a `pid` column and participates in `sample_metadata_triples` in `RdfGeneration`. Putting the columns on the shared type makes typed RDF output available to `Sample` exports as well, with no additional migration.
>
> **Do not add `rdf_value_type`/`rdf_datatype` to `extended_metadata_attributes`.**
This code delegates several RDF-related methods to the `sample_attribute_type` association:

```ruby
delegate :rdf_value_type, :rdf_datatype, :rdf_effective_value_type, :rdf_iri?,
         to: :sample_attribute_type, allow_nil: true
```

**What it does:**

- **Delegates** four methods (`rdf_value_type`, `rdf_datatype`, `rdf_effective_value_type`, `rdf_iri?`) to the associated `sample_attribute_type` object
- **`allow_nil: true`** means if `sample_attribute_type` is `nil`, these methods will return `nil` instead of raising a `NoMethodError`

**Context:**

`ExtendedMetadataAttribute` reuses RDF semantics from `SampleAttributeType` without duplicating the logic. When you call `extended_metadata_attribute.rdf_value_type`, it forwards to `extended_metadata_attribute.sample_attribute_type.rdf_value_type`. This allows extended metadata to piggyback on the existing RDF typing system used for sample attributes.

Tasks:
1. Add `rdf_value_type` (string, nullable, values: `"literal"`, `"iri"`, `"typed_literal"`, `"lang_literal"`) and `rdf_datatype` (string, nullable — XSD or other datatype URI) to `sample_attribute_types`
2. Write a migration for these two columns
3. Add `rdf_effective_value_type` and `rdf_iri?` delegation helpers to `ExtendedMetadataAttribute` reading from `sample_attribute_type.rdf_value_type`; add `RDF_VALUE_TYPES` constant
4. Write a `Seek::Rdf::RdfMapping` value object that wraps predicate IRI (from `pid`), value type and datatype (from `sample_attribute_type`), and provides `#build_rdf_object(value)` returning the correct `RDF::Term`
5. `RdfMapping.from_attribute(attr)` reads `attr.sample_attribute_type.rdf_value_type` and `attr.sample_attribute_type.rdf_datatype`
6. Write unit tests for `RdfMapping` covering all value types and edge cases

**Files created/modified**:
- `db/migrate/20260428083807_add_rdf_value_type_to_sample_attribute_types.rb` ✅
- `app/models/sample_attribute_type.rb` — `RDF_VALUE_TYPES`, `rdf_effective_value_type`, `rdf_iri?` ✅
- `app/models/extended_metadata_attribute.rb` — delegates `rdf_value_type`, `rdf_datatype`, `rdf_effective_value_type`, `rdf_iri?` to `sample_attribute_type` ✅
- `lib/seek/rdf/rdf_mapping.rb` — `RdfMapping` value object; `from_attribute` reads from `attr.sample_attribute_type` and works for both `ExtendedMetadataAttribute` and `SampleAttribute` ✅
- `config/initializers/seek_rdf.rb` — requires `rdf_mapping` ✅
- `.rubocop.yml` — `Style/Documentation` disabled, `Metrics/ClassLength` excluded for tests, `Naming/PredicateName` excluded for `extended_metadata_attribute.rb`, `db/migrate` excluded ✅
- `test/unit/rdf/rdf_mapping_test.rb` — 16 tests, 28 assertions, all green ✅

---

### Cycle 3: Enhanced metadata emitter (both ExtendedMetadata and Sample) ✅

**Goal**: Replace the minimal `extended_metadata_triples` and plain-literal `sample_metadata_triples` methods with a unified emitter that handles all four value types, array values, and graceful fallback, using the `rdf_value_type`/`rdf_datatype` from `SampleAttributeType` (Cycle 2).

> **Architecture note**: Keep the existing `extended_metadata_triples` and `sample_metadata_triples` hooks in `RdfGeneration`. Delegate each to a service class rather than refactoring the mixin. This is additive and non-breaking.

Tasks:
1. Create `Seek::Rdf::ExtendedMetadataEmitter` — takes a SEEK resource and an `RDF::Graph`, iterates `extended_metadata_type.extended_metadata_attributes`, and for each calls `RdfMapping.from_attribute(attr).build_rdf_object(value)`
2. Handle each `rdf_value_type` via `RdfMapping`:
   - `nil` / `"literal"` → plain `RDF::Literal` (backwards compatible)
   - `"lang_literal"` → `RDF::Literal(value, language: :en)`
   - `"typed_literal"` → `RDF::Literal(value, datatype: RDF::URI(rdf_datatype))`
   - `"iri"` → `RDF::URI(value)` — validate; fall back to plain literal + warn if invalid
3. Handle multi-valued fields (arrays) — emit one triple per element
4. For attributes with no `pid`: fall back to `seekh:` namespace with slugified title + log warning
5. Update `extended_metadata_triples` in `rdf_generation.rb` to delegate to `ExtendedMetadataEmitter`
6. Update `sample_metadata_triples` in `rdf_generation.rb` to also use `RdfMapping` (same logic, benefits `Sample` RDF export)
7. Write unit tests covering all value types, nil, invalid IRI, array, no-pid fallback, no-extended-metadata

**Files created/modified**:
- `lib/seek/rdf/extended_metadata_emitter.rb` — `ExtendedMetadataEmitter` service class ✅
- `lib/seek/rdf/rdf_generation.rb` — `extended_metadata_triples` delegates to emitter; `sample_metadata_triples` upgraded to use `RdfMapping` ✅
- `config/initializers/seek_rdf.rb` — requires `extended_metadata_emitter` ✅
- `.rubocop.yml` — exclusions for pre-existing `Metrics/ModuleLength`, `Metrics/MethodLength`, `Style/OptionalBooleanParameter`, `Lint/RescueException` in `rdf_generation.rb` ✅
- `test/unit/rdf/extended_metadata_emitter_test.rb` — 10 tests, 19 assertions, all green ✅

---

### Cycle 4: DCAT type assertions

**Goal**: Emit `dcat:Dataset` (and other DCAT class assertions) for the appropriate SEEK types, in addition to the existing JERM type triples.

> **Note**: `rdf_capable_types` is driven by `JERMVocab.defined_types.keys`. There is no separate DCAT type registry. The DCAT type assertions are emitted by a new `DcatEmitter` service (matching Cycle 3's pattern) hooked into `to_rdf_graph` via `dcat_type_triples`.

> **Pre-done (Cycle 1)**: `dcat` prefix is already registered in `ns_prefixes`. No change needed there.

Tasks:
1. Define a mapping from SEEK model class name → DCAT class (keyed by string to avoid model requires inside the service):
   - `DataFile`, `Assay` → `dcat:Dataset`
   - `Investigation`, `Study` → `dcat:Resource`
   - `Project` → `foaf:Project` (already in JERM as `jerm:Project`, skip to avoid duplication)
2. Create `Seek::Rdf::DcatEmitter` service — emits DCAT type triple + optional `dcat:Distribution` blank node
3. Emit `dcat:Distribution` as a blank node when `content_blob` is present and non-empty (`!content_blob.empty_file?`), including `dcat:accessURL`, `dcat:downloadURL` (constructed as `"#{rdf_resource}/download"`), `dcat:byteSize` (`xsd:decimal` if `file_size > 0`), `dct:format` (content type as plain literal)
4. Add `dcat_type_triples` hook to `to_rdf_graph` in `RdfGeneration`; require emitter in `seek_rdf.rb`
5. Write unit tests asserting DCAT type triples for each mapped class, Distribution blank node presence, byteSize and format triples, and no-op for unmapped classes / empty blobs

**Files created/modified**:
- `lib/seek/rdf/dcat_emitter.rb` — `DcatEmitter` service; `DCAT_CLASS_MAP` keyed by class name string; splits optional blob metadata into `emit_distribution_metadata` to satisfy Metrics cops ✅
- `lib/seek/rdf/rdf_generation.rb` — added `dcat_type_triples` step in `to_rdf_graph` ✅
- `config/initializers/seek_rdf.rb` — requires `dcat_emitter` ✅
- `test/unit/rdf/dcat_emitter_test.rb` — 13 tests, 28 assertions, all green ✅

---

### Cycle 5: Blank node support in ExtendedMetadataEmitter + DPV vocabulary

**Goal**: Extend the emitter to handle compound RDF structures (blank nodes) by leveraging SEEK's existing `linked_extended_metadata_type` mechanism. Define the DPV vocabulary for personal data / legal basis terms.

> **Architecture revision**: A separate `HealthDcatBuilder` is not needed. SEEK already has a first-class model for nested metadata: `ExtendedMetadataAttribute#linked_extended_metadata_type` links to a child `ExtendedMetadataType` whose attributes map to the blank node's sub-properties. Extending `ExtendedMetadataEmitter` to recurse into linked EMTs is both more generic and more aligned with SEEK's own data model. All HealthDCAT-AP blank node patterns (retentionPeriod, contactPoint, hasLegalBasis) are expressed as linked EMTs and are handled automatically.
>
> **Scalar patterns already handled (Cycles 2+3)**: `healthdcatap:healthCategory` (iri), `healthdcatap:populationCoverage` (lang_literal), `healthdcatap:trusteddataholder` (typed_literal/boolean), `dpv:hasPersonalData` (iri) — no new code needed for these.

> **DPV**: namespace `https://w3id.org/dpv#` — not in rdf-vocab gem, must be defined manually.

Tasks:
1. Create `lib/seek/rdf/vocabularies/dpv.rb` — defines `DPVVocab` with `hasPersonalData`, `hasLegalBasis`, `hasPurpose`, `LegalBasis`, `Purpose`
2. Extend `ExtendedMetadataEmitter#emit_attribute`:
   - When `attr.sample_attribute_type&.linked_extended_metadata_or_multi?`, call `emit_blank_node` for each nested `Seek::JSONMetadata::Data` value
   - Otherwise, fall through to the existing scalar path
3. Implement `emit_blank_node(subject, predicate, attr, data)`:
   - Collect all non-nil nested triples first; skip if none (avoids empty blank nodes)
   - Look up blank node `rdf:type` from `BLANK_NODE_TYPE_MAP` keyed by predicate URI string
   - Recurse into nested attributes using `RdfMapping` for scalar values
4. Define `BLANK_NODE_TYPE_MAP` for known predicates:
   - `dct:temporal`, `healthdcatap:retentionPeriod` → `dct:PeriodOfTime`
   - `dcat:contactPoint` → `vcard:Kind`
   - `dpv:hasLegalBasis` → `dpv:LegalBasis`
   - `dpv:hasPurpose` → `dpv:Purpose`
   - `healthdcatap:hdab` → `foaf:Agent`
5. Add `dpv` to `ns_prefixes` in `rdf_generation.rb`; require `dpv.rb` in `seek_rdf.rb`
6. Write unit tests covering: blank node created with correct type, nested triples emitted, no blank node for nil/empty data, multi-value blank nodes, unknown predicate blank node (no type)

**Files created/modified**:
- `lib/seek/rdf/vocabularies/dpv.rb` — `DPVVocab` for `hasPersonalData`, `hasLegalBasis`, `hasPurpose`, `LegalBasis`, `Purpose` ✅
- `lib/seek/rdf/extended_metadata_emitter.rb` — `BLANK_NODE_TYPE_MAP`; `emit_attribute` routes to `emit_blank_node` for linked EMT attrs; `collect_nested_triples` recurses into nested `Data` ✅
- `lib/seek/rdf/rdf_generation.rb` — `dpv` added to `ns_prefixes` ✅
- `config/initializers/seek_rdf.rb` — requires `dpv` ✅
- `.rubocop.yml` — `Metrics/AbcSize` excluded for `rdf_generation.rb` ✅
- `test/unit/rdf/extended_metadata_emitter_test.rb` — 6 new blank node tests added (16 total, 29 assertions, all green) ✅

---

### Cycle 6: Serialization and format wiring

**Goal**: Verify and extend the serialization layer; ensure `ns_prefixes` includes all new vocabularies; optionally expose RDF/XML as an additional format.

> **Codebase fact**: The controller layer already exists. `format.rdf { render template: 'rdf/show' }` is in `lib/seek/assets_standard_controller_actions.rb:20`. The `:rdf` MIME type is `text/turtle`. You do **not** need to create a new controller concern. The work here is: (a) ensuring `ns_prefixes` is complete, (b) optionally registering a `:rdfxml` MIME type if RDF/XML output is needed, and (c) verifying JSON-LD (`to_json_ld`) works with the new triples.

Tasks:
1. Ensure `ns_prefixes` in `RdfGeneration` includes `dcat`, `dcterms`, `healthdcatap`, `seekh` prefixes
2. Verify `to_json_ld` (already implemented in `rdf_generation.rb`) correctly compacts the new DCAT/HDCAT triples
3. If RDF/XML output is required, register a new `:rdfxml` MIME type in `config/initializers/mime_types.rb` and add `format.rdfxml { render plain: resource.to_rdfxml, content_type: 'application/rdf+xml' }` to the show action — note that `rdf/rdfxml` is already required in `seek_rdf.rb`
4. Write controller/request-level tests that GET a data file with `Accept: text/turtle` and assert: HTTP 200, correct content-type, presence of `dcat:Dataset` type triple in parsed response

**Files modified**:
- `lib/seek/rdf/rdf_generation.rb` — `ns_prefixes` already includes `dcat`, `dcterms`, `healthdcatap`, `seekh`, `dpv` (completed in Cycles 1–5) ✅
- `test/integration/rdf_response_test.rb` — 7 new Cycle 6 tests added (8 total, 28 assertions, all green); fixed `Lint/ShadowingOuterLocalVariable` in pre-existing test ✅

> **RDF/XML note**: `rdf/rdfxml` is already required in `seek_rdf.rb` (Cycle 1). No `:rdfxml` MIME type was added — the existing `:rdf` (`text/turtle`) format is the primary output per SEEK convention.

---

### Cycle 7: SHACL validation shapes

**Goal**: Provide machine-readable validation rules for the extended metadata profile.

Tasks:
1. Create `public/vocab/seek-healthdcat-shapes.ttl` — SHACL shapes document
2. Define `sh:NodeShape` for `dcat:Dataset` (SEEK-HealthDCAT profile):
   - `dct:title` — minCount 1, datatype `xsd:string`
   - `dct:description` — minCount 0, datatype `xsd:string`
   - `dcat:keyword` — minCount 0, datatype `xsd:string`
   - `dct:license` — minCount 1, nodeKind `sh:IRI`
   - `dct:accessRights` — minCount 1
   - `dcat:contactPoint` — minCount 0, class `vcard:Kind`
   - `healthdcatap:healthCategory` — minCount 1, nodeKind `sh:IRI`
   - `healthdcatap:trusteddataholder` — minCount 0, datatype `xsd:boolean`
   - `dpv:hasPersonalData` — minCount 0, nodeKind `sh:IRI` (categories from dpv-pd namespace)
3. Define `sh:NodeShape` for `dcat:Distribution`:
   - `dcat:accessURL` — minCount 1, nodeKind `sh:IRI`
   - `dct:format` — minCount 0
   - `dcat:byteSize` — minCount 0, datatype `xsd:decimal`
4. Write a rake task that runs SHACL validation against a generated RDF graph using the `shacl` gem or an external validator, useful for CI
5. Document shape file location and how to run validation in `docs/rdf_validation.md`

**Files created**:
- `public/vocab/seek-healthdcat-shapes.ttl` — 152 triples; `sh:NodeShape` for `dcat:Dataset` (17 property constraints) and `dcat:Distribution` (4 property constraints); `healthdcatap:healthCategory` and `dcat:accessURL` are `sh:Violation`-level, all others `sh:Warning` ✅
- `lib/tasks/rdf_validate.rake` — two tasks: `rdf:validate[file]` (single Turtle file) and `rdf:validate_fixtures` (all DataFiles in DB); no rubocop offenses ✅
- `docs/rdf_validation.md` — usage guide, shape tables, namespace reference, CI integration instructions ✅

---

### Cycle 8: Seed data & example output

**Goal**: Provide a working end-to-end example and seed data for development/testing.

#### Concrete example: COVID-19 Patient Registry

This is the canonical example dataset used throughout this cycle. It is a `DataFile` (→ `dcat:Dataset`) representing a clinical registry, with a nested population blank node modelled via `linked_extended_metadata_type`.

**Target Turtle output** (what the RDF export should produce after all cycles are complete):

```turtle
@prefix dcat:         <http://www.w3.org/ns/dcat#> .
@prefix dct:          <http://purl.org/dc/terms/> .
@prefix healthdcatap: <http://healthdataportal.eu/ns/health#> .
@prefix dpv:          <https://w3id.org/dpv#> .
@prefix foaf:         <http://xmlns.com/foaf/0.1/> .
@prefix jerm:         <http://jermontology.org/ontology/JERMOntology#> .
@prefix dcterms:      <http://purl.org/dc/terms/> .

<https://seek.example.org/data_files/1>
    a dcat:Dataset, jerm:Data ;

    # Core SEEK fields (existing rdf_mappings.csv — unchanged)
    dcterms:title       "COVID-19 Patient Registry" ;
    dcterms:description "Clinical data of hospitalized COVID-19 patients" ;
    jerm:title          "COVID-19 Patient Registry" ;

    # New DCAT-AP triples (Cycle 4)
    dcat:keyword   "COVID-19", "clinical", "registry" ;

    # HealthDCAT-AP mandatory fields from extended metadata (Cycles 2–5)
    healthdcatap:healthCategory <http://13.81.34.152:1101/resource/authority/healthcategories/INFECTIOUS_DISEASE> ;

    # HealthDCAT-AP optional fields
    healthdcatap:populationCoverage "Adult hospitalized COVID-19 patients aged 18-65"@en ;
    healthdcatap:minTypicalAge      18 ;
    healthdcatap:maxTypicalAge      65 ;
    healthdcatap:numberOfRecords    "50000"^^xsd:nonNegativeInteger ;
    healthdcatap:trusteddataholder  true^^xsd:boolean ;
    healthdcatap:hasCodingSystem    <https://www.wikidata.org/entity/Q82821> ;  # ICD-10
    healthdcatap:retentionPeriod    [
        a dct:PeriodOfTime ;
        dcat:startDate "2020-03-01"^^xsd:date ;
        dcat:endDate   "2030-12-31"^^xsd:date
    ] ;

    # Personal data and legal basis via DPV (not healthdcatap namespace)
    dpv:hasPersonalData dpv-pd:HealthRecord, dpv-pd:Age ;
    dpv:hasLegalBasis   [ a dpv:LegalBasis ; dct:description "Art. 9(2)(j) GDPR — scientific research"@en ] ;

    dct:accessRights <http://publications.europa.eu/resource/authority/access-right/RESTRICTED> ;

    dct:publisher [
        a foaf:Organization ;
        foaf:name "Example Hospital"
    ] .
```

**Mapping: core fields vs extended metadata**

| Turtle property | Source in SEEK | Notes |
|---|---|---|
| `dcterms:title`, `jerm:title` | `DataFile#title` | Core field, existing `rdf_mappings.csv` |
| `dcterms:description` | `DataFile#description` | Core field |
| `dcat:keyword` | SEEK tags | Via tagging system (Cycle 4) |
| `healthdcatap:healthCategory` | Extended metadata attribute, `pid: 'http://healthdataportal.eu/ns/health#healthCategory'` | IRI value type |
| `healthdcatap:populationCoverage` | Extended metadata attribute, `pid: 'http://healthdataportal.eu/ns/health#populationCoverage'` | Lang-tagged literal |
| `healthdcatap:minTypicalAge` / `maxTypicalAge` | Extended metadata attributes | `xsd:integer` typed literals |
| `healthdcatap:trusteddataholder` | Extended metadata attribute, `pid: 'http://healthdataportal.eu/ns/health#trusteddataholder'` | `xsd:boolean` typed literal |
| `healthdcatap:retentionPeriod` | Extended metadata attribute, `pid: 'http://healthdataportal.eu/ns/health#retentionPeriod'` | `dct:PeriodOfTime` blank node (Cycle 5) |
| `dpv:hasPersonalData` | Extended metadata attribute, `pid: 'https://w3id.org/dpv#hasPersonalData'` | IRI — **DPV namespace**, not healthdcatap |
| `dpv:hasLegalBasis` | Extended metadata attribute, `pid: 'https://w3id.org/dpv#hasLegalBasis'` | Blank node — **DPV namespace**, not healthdcatap |
| `dct:accessRights` | Extended metadata attribute, `pid: 'http://purl.org/dc/terms/accessRights'` | IRI value type |
| `dct:publisher` | Linked `Project` / `Institution` (Cycle 4) | Emitted as `foaf:Organization` blank node |

**Seed file skeleton** (`db/seeds/extended_metadata_drafts/healthdcat_covid19_example.seeds.rb`):

```ruby
HDCAT_NS = 'http://healthdataportal.eu/ns/health#'.freeze
DPV_NS   = 'https://w3id.org/dpv#'.freeze
DCT_NS   = 'http://purl.org/dc/terms/'.freeze

disable_authorization_checks do
  # Outer type: HealthDCAT-AP DataFile metadata
  unless ExtendedMetadataType.where(title: 'HealthDCAT-AP Health Dataset', supported_type: 'DataFile').any?
    emt = ExtendedMetadataType.new(title: 'HealthDCAT-AP Health Dataset', supported_type: 'DataFile')
    emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(
      title: 'health_category', label: 'Health Category',
      description: 'IRI of a health domain category (ICD-10, ICD-11, SNOMED CT)',
      pid: "#{HDCAT_NS}healthCategory",
      sample_attribute_type: SampleAttributeType.where(title: 'String').first
    )
    emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(
      title: 'population_coverage', label: 'Population Coverage',
      pid: "#{HDCAT_NS}populationCoverage",
      sample_attribute_type: SampleAttributeType.where(title: 'Text').first
    )
    emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(
      title: 'trusted_data_holder', label: 'Trusted Data Holder',
      description: 'Whether this is a trusted data holder under EHDS',
      pid: "#{HDCAT_NS}trusteddataholder",
      sample_attribute_type: SampleAttributeType.where(title: 'Boolean').first
    )
    # dpv:hasPersonalData — note DPV namespace, not HDCAT
    emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(
      title: 'personal_data_categories', label: 'Personal Data Categories',
      description: 'Categories of personal data (dpv-pd: IRIs, e.g. dpv-pd:HealthRecord)',
      pid: "#{DPV_NS}hasPersonalData",
      sample_attribute_type: SampleAttributeType.where(title: 'String').first
    )
    # dpv:hasLegalBasis — note DPV namespace, not HDCAT
    emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(
      title: 'legal_basis', label: 'Legal Basis',
      description: 'GDPR legal basis description (DPV vocabulary)',
      pid: "#{DPV_NS}hasLegalBasis",
      sample_attribute_type: SampleAttributeType.where(title: 'Text').first
    )
    emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(
      title: 'access_rights', label: 'Access Rights',
      description: 'URI from EU Publications Office access-right vocabulary',
      pid: "#{DCT_NS}accessRights",
      sample_attribute_type: SampleAttributeType.where(title: 'String').first
    )
    emt.save!
  end
end
```

> **Note on `pid` and value types**: The `pid` column already exists and is already read by `extended_metadata_triples`. In this cycle the seed uses plain string values for IRI fields (`health_category`, `access_rights`). After Cycle 2 adds `rdf_value_type`/`rdf_datatype` columns, update these attributes to `rdf_value_type: 'iri'` so they emit `RDF::URI` objects rather than string literals.

Tasks:
1. Create `db/seeds/extended_metadata_drafts/healthdcat_covid19_example.seeds.rb` using the skeleton above — seeds the two `ExtendedMetadataType` records (Population inner type + HealthDCAT-AP outer type) plus one `DataFile` instance with the COVID-19 registry values
2. The seeded `DataFile` must be attached to an `Investigation → Study → Assay` hierarchy so the full ISA context is present in the RDF
3. Set `rdf_value_type: 'iri'` on the `health_category` and `access_rights` attributes (after Cycle 2 migration has run)
4. Generate and save example Turtle and JSON-LD output files to `docs/examples/`
5. Write a rake task `rake rdf:generate_examples` that regenerates these files from the seeded data
6. These example files serve as regression test fixtures — add tests that parse them and assert key triples, including the nested population blank node

**Files created/modified**:
- `db/seeds/extended_metadata_drafts/healthdcat_covid19_example.seeds.rb` — seeds two EMTs (HealthDCAT Retention Period inner + HealthDCAT-AP Health Dataset outer), ISA hierarchy (Investigation → Study → Assay), and DataFile with all HealthDCAT-AP values ✅
- `lib/tasks/rdf_examples.rake` — `rake rdf:generate_examples` writes Turtle + JSON-LD to `docs/examples/` ✅
- `docs/examples/covid19_registry.ttl` — generated Turtle with `dcat:Dataset`, `healthdcatap:healthCategory` (IRI), `healthdcatap:retentionPeriod` (blank node), `dpv:hasPersonalData` (IRI), `dct:accessRights` (IRI) ✅
- `docs/examples/covid19_registry.jsonld` — generated JSON-LD ✅
- `test/integration/rdf/healthdcat_example_test.rb` — 9 tests, 30 assertions, all green ✅
- `lib/seek/rdf/extended_metadata_emitter.rb` — bug fix: `emit_blank_node` now handles plain `Hash` values (from `get_attribute_value`) in addition to `Seek::JSONMetadata::Data` objects ✅

---

### Cycle 9: Application profile documentation

**Goal**: Produce a human-readable and machine-readable specification of the SEEK-HealthDCAT profile.

Tasks:
1. Create `docs/seek_healthdcat_ap.md` — the application profile document including:
   - Namespace declarations table
   - Class usage table (SEEK entity → RDF class)
   - Property table per class with: property URI, obligation (M/R/O), source vocab, value type, notes
   - Worked Turtle example (inline)
   - Guidance on how to add a new extended metadata type with correct RDF mapping (set `pid`, `rdf_value_type`, `rdf_datatype` on each attribute)
2. Create `public/vocab/seek-healthdcat-ap.jsonld` — JSON-LD context file for the profile
3. Create `public/vocab/seekh.ttl` — Turtle definition of the `seekh:` namespace terms (OWL/RDFS declarations)
4. Add a route exposing `seekh.ttl` at a stable URI (e.g. `/vocab/seekh`) with content negotiation

**Files created/modified**:
- `docs/seek_healthdcat_ap.md` — namespace table, class mapping, property tables (always-emitted + Distribution + HealthDCAT-AP extended metadata), blank node structure patterns, worked Turtle example, guide for adding new EMT types ✅
- `public/vocab/seek-healthdcat-ap.jsonld` — JSON-LD context declaring all namespaces and IRI/typed-literal `@type` annotations for IRI-valued and numeric properties ✅
- `public/vocab/seekh.ttl` — OWL Ontology declaration for `seekh:` namespace with `rdfs:label`, `rdfs:comment`, version info ✅
- `config/routes.rb` — `get '/vocab/seekh', to: redirect('/vocab/seekh.ttl')` added ✅

> **Discovery during Cycle 9 documentation**: SEEK has two independent JSON-LD export pipelines that share the `application/ld+json` MIME type — creating an ambiguity that needs resolution (see below).

---

### Cycle 9.5: `/dcat` endpoint — DCAT-AP / HealthDCAT-AP JSON-LD exposure

**Problem**: SEEK has two completely independent JSON-LD export mechanisms:

| Pipeline | Method | Controller hook | Format | Vocabulary |
|---|---|---|---|---|
| Bioschemas | `to_schema_ld` | `format.jsonld { render body: asset_version.to_schema_ld }` | `application/ld+json` | Schema.org (`@context: "https://schema.org"`) |
| RDF graph | `to_json_ld` | none (only callable directly) | — | JERM + DCAT + HealthDCAT-AP |

Both pipelines produce JSON-LD, but for different consumer audiences. The `application/ld+json` MIME type is already claimed by the Bioschemas pipeline. The RDF-graph `to_json_ld` (our HealthDCAT-AP output) has no public URL.

**Solution**: A dedicated `/dcat` member action on all RDF-capable resources:
- `GET /data_files/:id/dcat` with `Accept: text/turtle` → DCAT Turtle (same as `:rdf`, explicit endpoint)
- `GET /data_files/:id/dcat` with `Accept: application/ld+json` → DCAT JSON-LD (`to_json_ld`)
- Existing `GET /data_files/:id` with `Accept: application/ld+json` → Bioschemas **unchanged**

The action lives in `Seek::AssetsStandardControllerActions` (shared by all asset controllers via `Seek::AssetsCommon`). The route is added to both the `:asset` and `:isa` concerns so all DCAT-mapped resource types (DataFile, Assay, Investigation, Study, and others) gain the endpoint automatically.

**Files created/modified**:
- `lib/seek/assets_standard_controller_actions.rb` — `dcat` action added ✅
- `config/routes.rb` — `get :dcat` added to `:asset` and `:isa` concerns ✅
- `test/integration/rdf_response_test.rb` — tests for `/dcat` endpoint: Turtle, JSON-LD, and backwards-compatibility of Bioschemas ✅

---

### Cycle 10: Regression & backwards compatibility tests ✅

**Goal**: Guarantee that nothing in the existing RDF export is broken.

**Files created/modified**:
- `test/integration/rdf/rdf_backwards_compat_test.rb` — 22 tests, 72 assertions, all green ✅

**What is tested**:
- **Group 1** — JERM triples regression: DataFile, Assay, Investigation, Sop all still emit `jermontology` type, `jerm:title`, `jerm:seekID`, and DC `dct:title` triples
- **Group 2** — DCAT/JERM coexistence: DataFile and Assay emit both JERM type and `dcat:Dataset` simultaneously; Sop and resources not in `DCAT_CLASS_MAP` gain no spurious DCAT type; Investigation gets `dcat:Resource` (not `dcat:Dataset`)
- **Group 3** — DCAT-AP 3.0 mandatory fields: DataFile with title + description + content_blob satisfies `dcat:Dataset`, `dct:title`, `dct:description`, and `dcat:distribution`; Distribution blank node has `dcat:downloadURL`, `dcat:accessURL`, and `dcat:Distribution` type
- **Group 4** — HealthDCAT-AP EMT attached: adding HealthDCAT extended metadata does not clobber existing JERM type, `dcat:Dataset`, `dct:title`, or `jerm:seekID` triples
- **Group 5** — All statements in generated graphs are valid RDF

Tasks:
1. ✅ Golden-file approach rejected in favour of semantic triple-pattern assertions (resource URIs embed DB IDs, making exact string diffs fragile across test runs)
2. ✅ Tests assert that removing any triple from Groups 1–4 triggers a test failure
3. ✅ JERM type triples explicitly asserted alongside `dcat:` triples
4. ✅ DCAT-AP 3.0 mandatory consumer properties verified for DataFile and Assay
5. ✅ Full RDF test suite (56 tests across all RDF test files) passes with 0 failures

---

## Code Quality Constraints

Follow these throughout all cycles:

- **No monkey-patching** of existing serializer classes — extend via composition or clearly scoped subclasses
- **Fail gracefully** — if an extended metadata field has no `pid` and no obvious mapping, log a warning and skip (do not raise)
- **IRI validation** — before emitting any IRI, validate it is well-formed (`RDF::URI(value).valid?`). Invalid IRIs become string literals with a log warning
- **Language tagging** — all free-text literals should be language-tagged (`@en` as default, configurable)
- **No N+1 queries** — when serializing a catalog or list, eager-load extended metadata associations
- **Idempotent serialization** — serializing the same resource twice must produce byte-identical output (sort triples deterministically)
- **Test coverage** — every new class needs unit tests; every new API endpoint behaviour needs integration tests
- **DC vs DCTERMS** — the existing `rdf_mappings.csv` uses `RDF::Vocab::DC` (DC Elements 1.1). New DCAT-AP properties use `RDF::Vocab::DCTERMS`. Do not replace the existing mappings.

---

## Key External References

Before starting, read/skim these (use web search if needed):

1. **HealthDCAT-AP specification**: `https://github.com/SEMICeu/HealthDCAT-AP` — the authoritative source for property URIs, cardinalities, and controlled vocabularies
2. **DCAT-AP 3.0**: `https://semiceu.github.io/DCAT-AP/releases/3.0.0/` — base application profile
3. **W3C DCAT 3**: `https://www.w3.org/TR/vocab-dcat-3/` — core vocabulary spec
4. **rdf-vocab gem**: `https://github.com/ruby-rdf/rdf-vocab` — check what's already available vs what needs manual definition
5. **Löbe et al. 2021**: The paper uploaded in this conversation — read Table 1 (entity mapping) and Table 2 (property mapping) as your baseline
6. **SEEK codebase**: `https://github.com/seek4science/seek` — specifically `lib/seek/rdf/` and `app/models/extended_metadata*.rb`

---

## Definition of Done

Each cycle is complete when:
- All specified files exist and pass `rubocop` linting
- All specified tests pass (`rails test` or `rspec`)
- No existing tests are broken
- The cycle's deliverable is documented in the relevant `docs/` file

The overall task is complete when:
- A DataFile with health extended metadata serializes to valid Turtle containing `dcat:Dataset`, at least one `healthdcatap:` property, and `seekh:` terms for any unmapped fields
- The output validates against the SHACL shapes defined in Cycle 7
- Existing DCAT consumers receive unchanged output for resources without health extended metadata
- All 10 cycles are complete and passing
