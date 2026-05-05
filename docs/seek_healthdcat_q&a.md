# SEEK HealthDCAT-AP Implementation — Q&A

Running log of questions asked during development. Updated each cycle.

---

## RDF Pipeline & Infrastructure

### Q: What is `config/sparql_queries.yml` for?

It stores named SPARQL SELECT queries that SEEK runs against a Virtuoso triple store. Each entry has a key (the query name) and a SPARQL string. The queries are executed by `Seek::Rdf::VirtuosoEndpoint` to power the "Related items" / semantic search features — e.g. finding assays that share a type with a given dataset. They are NOT used during RDF generation; they are read-side queries run after data has been pushed to Virtuoso.

---

### Q: What is `lib/seek/rdf/rdf_mappings.csv` for?

It is a declarative mapping table that drives `generate_from_csv_definitions` — one of the four steps in `to_rdf_graph`. Each row maps a SEEK model attribute to an RDF predicate and an optional datatype. The RDF generation pipeline reads each row and, for every resource that responds to the named attribute, emits the corresponding triple.

**Example — one row and its effect:**

```
model,attribute,predicate,datatype
DataFile,title,http://purl.org/dc/terms/title,
```

For a `DataFile` with `title = "My dataset"`, the pipeline calls `attribute_value = resource.title` and emits:

```turtle
<https://seek.example.org/data_files/1>
    dct:title "My dataset" .
```

The CSV handles the "flat" scalar attributes. Complex/nested structures (blank nodes, HealthDCAT extensions) are handled by the `additional_triples` and `extended_metadata_triples` hooks instead.

---

### Q: Is `rdf_value_type`/`rdf_datatype` on `SampleAttributeType` + `RdfMapping` the same mechanism as `rdf_mappings.csv`?

No — they solve a similar sub-problem ("given a source value, emit the right RDF term") but operate on completely different data sources and at different layers. They are complementary pipelines, not duplicates.

| Dimension | `rdf_mappings.csv` | `rdf_value_type` + `RdfMapping` |
|---|---|---|
| **Data source** | Core SEEK model attributes (`DataFile#title`, `Person#name`, …) | Dynamic extended metadata field values stored as JSON |
| **Predicate** | Defined in the CSV file per row | Defined in the `pid` column on `ExtendedMetadataAttribute` / `SampleAttribute` |
| **Value type config** | Single `u`/`l` flag (URI or literal) in the CSV | 4 types (`literal`, `lang_literal`, `typed_literal`, `iri`) stored in DB on `SampleAttributeType` |
| **Datatype** | Not configurable — always plain literal or URI | Any XSD/OWL datatype URI stored in `SampleAttributeType#rdf_datatype` |
| **Configuration location** | Static file, deploy-time | Database, seed/UI-time |
| **Pipeline step** | `generate_from_csv_definitions` (step 2 of `to_rdf_graph`) | `extended_metadata_triples` (step 4 of `to_rdf_graph`) |
| **Scope** | ~80 fixed core fields across all SEEK types | Unlimited, user-defined metadata fields |

In short: the CSV pipeline handles what SEEK already knows about a resource (title, creator, dates…). The `RdfMapping` pipeline handles what users have declared about a resource via extended metadata (health category, population coverage, number of records…). Both feed into the same `RDF::Graph` but never overlap.

---

### Q: Can we model a HealthDCAT-AP dataset in SEEK? What resource type should it be?

Yes. A `DataFile` is the best fit — it already maps to `dcat:Dataset` in the RDF pipeline and supports versioning, DOI minting, and policy-based access control.

The core SEEK fields (title, description, creator, license, keywords) cover most `dcat:Dataset` mandatory properties. The HealthDCAT-AP-specific properties that have no SEEK equivalent (e.g. `health:healthCategory`, `health:populationCoverage`, `health:numberOfRecords`) are added via **Extended Metadata** — a `ExtendedMetadataType` schema attached to the `DataFile`.

**Mapping summary for the COVID-19 registry example:**

| HealthDCAT-AP property | SEEK mechanism |
|---|---|
| `dct:title` | `DataFile#title` |
| `dct:description` | `DataFile#description` |
| `dct:license` | `DataFile#license` |
| `dcat:keyword` | `DataFile` tags |
| `dcat:theme` | controlled vocabulary annotation |
| `health:healthCategory` | ExtendedMetadata (`rdf_value_type: iri`) |
| `health:populationCoverage` | ExtendedMetadata (`rdf_value_type: lang_literal`) |
| `health:numberOfRecords` | ExtendedMetadata (`rdf_value_type: typed_literal`, `rdf_datatype: xsd:integer`) |
| `health:minTypicalAge` | ExtendedMetadata (`rdf_value_type: typed_literal`, `rdf_datatype: xsd:integer`) |
| `dpv:hasPersonalData` | ExtendedMetadata (`rdf_value_type: iri`) |

---

### Q: Where do all the properties defined in `lib/seek/rdf/vocabularies/health_dcat.rb` come from?

They come from the official **HealthDCAT-AP Release 6** specification, sourced from the EU Code repository at `https://code.europa.eu/healthdataeu/healthdcat-ap`. Specifically, the property list was verified against the Release 6 Turtle example files (`healthdcatap_*.ttl`) in `public/releases/release-6/examples/`.

Key corrections made after auditing the examples:

| Original guess | Correct Release 6 term |
|---|---|
| `minimumTypicalAge` | `minTypicalAge` |
| `maximumTypicalAge` | `maxTypicalAge` |
| `codingSystem` | `hasCodingSystem` |
| `codeValues` | `hasCodeValues` |
| `healthdcatap:personalData` | `dpv:hasPersonalData` (W3C DPV namespace, not healthdcatap) |

The namespace is `http://healthdataportal.eu/ns/health#` (prefix `healthdcatap`), not the GitHub Pages URL.

---

## Extended Metadata RDF Columns (Cycle 2)

### Q: What are the `rdf_value_type` and `rdf_datatype` columns on `extended_metadata_attributes` for?

They tell SEEK how to serialize a custom metadata field into RDF when generating a dataset's Turtle/RDF export.

**The problem they solve:** A plain Ruby string like `"true"` could mean different things in RDF — a plain text literal, a boolean, a URI, etc. Without these columns every extended metadata value gets emitted as a generic string literal, which is semantically wrong for typed or IRI values.

**Concrete example — a HealthDCAT-AP "health category" field:**

| column | value |
|---|---|
| `pid` | `http://healthdataportal.eu/ns/health#healthCategory` |
| `rdf_value_type` | `iri` |
| `rdf_datatype` | *(null — only used for typed_literal)* |

When the attribute value is `"http://13.81.34.152:1101/resource/authority/healthcategories/EHRS"`, the emitter produces:

```turtle
<dataset/123> health:healthCategory <http://13.81.34.152:1101/resource/authority/healthcategories/EHRS> .
```

Without the column it would wrongly emit a string literal:

```turtle
<dataset/123> health:healthCategory "http://13.81.34.152:1101/resource/authority/healthcategories/EHRS" .
```

**The four value types:**

| `rdf_value_type` | `rdf_datatype` | use case |
|---|---|---|
| `literal` (default) | — | free-text, e.g. a description |
| `lang_literal` | — | human-readable label needing `@en` tag |
| `typed_literal` | e.g. `xsd:integer` | numeric/boolean — `numberOfRecords`, `minTypicalAge` |
| `iri` | — | controlled vocabulary term stored as a URI |

---

### Q: `pid` in `extended_metadata_attributes` is a persistent identifier — can it be an IRI?

Yes. `pid` is the persistent identifier for the attribute and acts as the **RDF predicate URI**. For example:

```
pid = "http://healthdataportal.eu/ns/health#healthCategory"
```

So `pid` answers **"what property is this?"** (the predicate), while `rdf_value_type` answers **"how should the value be serialized?"** (the object type).

In a triple:

```
<subject>  <pid>  <object built from rdf_value_type + value>
```

`RdfMapping` wraps both: `pid` becomes the predicate `RDF::URI`, and `rdf_value_type`/`rdf_datatype` determine how the stored Ruby value is turned into the correct `RDF::Term`.

---

### Q: Could Cycle 2 have been implemented without adding columns to `extended_metadata_attributes`?

Yes, two alternatives existed:

**Option A — Infer from `sample_attribute_type.base_type`** (no migration needed)

Map the existing SEEK base type to an RDF type at emit time:

| `base_type` | RDF output |
|---|---|
| `String` | plain literal |
| `Integer` | `xsd:integer` typed literal |
| `Float` | `xsd:decimal` typed literal |
| `Boolean` | `xsd:boolean` typed literal |
| `URI` | `RDF::URI` (iri) |

Limitation: can't express `lang_literal`, can't override the XSD datatype (e.g. `xsd:date` vs `xsd:dateTime`).

**Option B — External YAML config keyed by `pid`**

A file like `config/rdf_attribute_types.yml` mapping each predicate URI to its value type. No DB migration, but config and seed data can drift apart, and doesn't apply to ad-hoc `pid` values.

The column approach was chosen because `rdf_value_type` and `rdf_datatype` sit next to `pid` on the same record — the RDF mapping is self-contained per attribute, fully expressive (all 4 value types, any XSD datatype), and survives seed migrations cleanly.

---

### Q: Can an extended metadata attribute have no RDF output?

Yes. Current scenarios:

- **`pid` is blank** — no predicate to build a triple with. The emitter currently falls back to `seekh:` namespace rather than skipping entirely.
- **Value is nil or blank** — emitter skips it (correct behaviour).
- **UI-only / private fields** — helper text, internal notes, admin fields not meant for public export. The emitter has no opt-out flag today, so these still get emitted under `seekh:` if they have a value.

There is currently no `rdf_suppress` / `emit_rdf: false` column to explicitly exclude an attribute from RDF output. That could be added in a later cycle if needed.

---

### Q: Why add `rdf_value_type` / `rdf_datatype` to `extended_metadata_attributes` rather than to `sample_attribute_types`? Can it be shared?

**Correction first:** `SampleAttribute` *does* have an RDF export concern. It has a `pid` column and participates in `sample_metadata_triples` in `rdf_generation.rb`, which is called for every `Sample` object during RDF export:

```ruby
# rdf_generation.rb
def sample_metadata_triples(rdf_graph)
  attributes = sample_type.sample_attributes.select { |at| at.pid.present? }
  attributes.each do |attribute|
    rdf_graph << [resource, RDF::URI(attribute.pid), RDF::Literal(get_attribute_value(attribute))]
  end
end
```

So both `SampleAttribute` and `ExtendedMetadataAttribute` share:
- The `pid` column (RDF predicate)
- The `Seek::JSONMetadata::Attribute` concern (which defines `belongs_to :sample_attribute_type`)
- The same plain-literal-only limitation before Cycle 2

**Why `SampleAttributeType` is still not the right place:**

`SampleAttributeType` has a `base_type` field, but SEEK's base types are: `String`, `Integer`, `Float`, `Boolean`, `DateTime`, `Date`, `Text`, `CV`, `SeekSample`, etc. — **there is no `URI` / `IRI` base type**. So inferring `rdf_value_type: 'iri'` from the base type is not possible. Language-tagged literals (`lang_literal`) also have no corresponding base type.

The granularity problem also remains — two `String` attributes on the same type can need different RDF treatment:

```
title: "population_coverage",  pid: "health:populationCoverage",  rdf_value_type: "lang_literal"
title: "dataset_id",           pid: "dct:identifier",             rdf_value_type: "literal"
```

**Decision: put the columns on `SampleAttributeType` — not on the attribute tables.**

After further investigation (see Q below), the correct layer is `sample_attribute_types`. Both `ExtendedMetadataAttribute` and `SampleAttribute` already share `SampleAttributeType` via `belongs_to :sample_attribute_type` (defined in the shared `Seek::JSONMetadata::Attribute` concern). Putting `rdf_value_type`/`rdf_datatype` there means both models inherit typed RDF output automatically — no duplication, no separate migration for `SampleAttribute`. Cycles 2 and 3 were rewritten accordingly.

---

## Extended Metadata Emitter (Cycle 3)

### Q: What does `ExtendedMetadataEmitter` do, and why is it a separate class?

Before Cycle 3, `extended_metadata_triples` in `rdf_generation.rb` was an inline method that always emitted every value as a plain `RDF::Literal`, regardless of `rdf_value_type`. It also skipped attributes without a `pid` silently.

`Seek::Rdf::ExtendedMetadataEmitter` replaces that inline logic with a dedicated service that:

1. Iterates all attributes of the resource's `ExtendedMetadataType`
2. For each attribute, calls `RdfMapping.from_attribute(attr).build_rdf_object(value)` — which applies the correct `rdf_value_type` / `rdf_datatype` from Cycle 2
3. Handles **array values** — emits one triple per element
4. For attributes **without a `pid`**, falls back to the `seekh:` namespace using a slugified attribute title, and logs a warning

The refactored `extended_metadata_triples` becomes a single delegation line:

```ruby
def extended_metadata_triples(rdf_graph)
  Seek::Rdf::ExtendedMetadataEmitter.new(self, rdf_graph).emit
end
```

---

### Q: How does `ExtendedMetadataEmitter` fall back when an attribute has no `pid`?

It slugifies the attribute title using `parameterize(separator: '_')` and emits under the `seekh:` namespace (`https://seek4science.org/vocab/seekh#`). For example, an attribute titled `"population coverage"` with no `pid` emits as:

```turtle
<dataset/123> seekh:population_coverage "adults" .
```

A `Rails.logger.warn` is also emitted so the missing `pid` is visible in logs. This is intentionally permissive — extended metadata that predates the RDF columns still produces *some* RDF output rather than silently dropping data.

---

### Q: Why does `sample_metadata_triples` also use `RdfMapping` after Cycle 3?

Before Cycle 3, `sample_metadata_triples` emitted every value as a plain `RDF::Literal`:

```ruby
rdf_graph << [resource, RDF::URI(attribute.pid), RDF::Literal(get_attribute_value(attribute))]
```

After Cycle 3 it uses `RdfMapping.from_attribute(attribute)`:

```ruby
mapping    = Seek::Rdf::RdfMapping.from_attribute(attribute)
rdf_object = mapping.build_rdf_object(get_attribute_value(attribute))
rdf_graph << [subject, RDF::URI(attribute.pid), rdf_object] if rdf_object
```

`SampleAttribute` shares the same `belongs_to :sample_attribute_type` association as `ExtendedMetadataAttribute`. Once `rdf_value_type`/`rdf_datatype` were added to `SampleAttributeType` in Cycle 2, there is no reason for `Sample` RDF exports to remain plain-literal-only. The upgrade is purely additive — existing `Sample` seeds and fixtures have `rdf_value_type: nil`, which `RdfMapping` treats as `"literal"`, so the output is identical to before.

---

### Q: What tests cover Cycle 3?

`test/unit/rdf/extended_metadata_emitter_test.rb` (10 tests, 19 assertions):

| Test | What it checks |
|---|---|
| `emits plain literal for default (nil) rdf_value_type` | Backwards-compatible plain literal when no RDF type is configured |
| `emits typed literal when rdf_value_type is typed_literal` | XSD datatype is attached to the literal |
| `emits language-tagged literal when rdf_value_type is lang_literal` | `@en` language tag present |
| `emits RDF::URI when rdf_value_type is iri and value is valid` | Valid IRI emitted as `RDF::URI`, not a literal |
| `falls back to plain literal when iri value is invalid` | Invalid IRI string falls back to `RDF::Literal` |
| `skips nil values` | No triple emitted for nil attribute value |
| `skips blank values` | No triple emitted for empty-string value |
| `emits one triple per element for array values` | 3-element array → 3 triples |
| `falls back to seekh namespace when pid is absent` | `seekh:population_coverage` used when `pid` is nil |
| `returns graph unchanged when resource has no extended metadata` | Early return — graph stays empty |

---

## DCAT Type Assertions (Cycle 4)

### Q: What does `DcatEmitter` do, and which SEEK classes get DCAT type triples?

`Seek::Rdf::DcatEmitter` adds DCAT `rdf:type` assertions for SEEK resource types that correspond to standard DCAT classes. It also emits a `dcat:Distribution` blank node for resources that have a downloadable `ContentBlob`.

**Class → DCAT type mapping** (`DCAT_CLASS_MAP`):

| SEEK class | DCAT type |
|---|---|
| `DataFile` | `dcat:Dataset` |
| `Assay` | `dcat:Dataset` |
| `Investigation` | `dcat:Resource` |
| `Study` | `dcat:Resource` |
| All others | no DCAT type emitted |

`Project` already maps to `jerm:Project` and `foaf:Project` is already in the JERM vocab, so it is intentionally excluded to avoid duplicating a triple that already exists.

The emitter is keyed by **class name string** (not the constant) to avoid requiring model constants inside the service file.

---

### Q: How is `dcat:Distribution` structured for a DataFile?

When a resource has a non-empty `ContentBlob` (`!content_blob.empty_file?`), the emitter creates a blank node:

```turtle
<data_files/123>
    dcat:distribution [
        a dcat:Distribution ;
        dcat:accessURL  <data_files/123/download> ;
        dcat:downloadURL <data_files/123/download> ;
        dcat:byteSize   "204800"^^xsd:decimal ;     # omitted if file_size is 0
        dct:format      "application/pdf"            # omitted if content_type is blank
    ] .
```

The download URL is constructed as `"#{rdf_resource}/download"` — appending `/download` to the dataset's own URI. This matches SEEK's named route pattern (`download_data_file GET /data_files/:id/download`).

`dct:format` is emitted as a plain literal (the MIME type string). Mapping to a formal IANA IRI (`https://www.iana.org/assignments/media-types/…`) is deferred to a later cycle.

---

### Q: Why does `to_rdf_graph` now have five steps instead of four?

Cycle 4 adds a `dcat_type_triples` step between `additional_triples` and `extended_metadata_triples`:

```ruby
def to_rdf_graph
  rdf_graph = describe_type(rdf_graph)             # JERM type triple
  rdf_graph = generate_from_csv_definitions(...)   # CSV-driven core fields
  rdf_graph = additional_triples(rdf_graph)         # SBML format flag
  rdf_graph = dcat_type_triples(rdf_graph)          # NEW: DCAT class + Distribution
  rdf_graph = extended_metadata_triples(rdf_graph)  # typed EM triples
  rdf_graph = sample_metadata_triples(rdf_graph) if is_a?(Sample)
  rdf_graph
end
```

Placing it after `additional_triples` and before `extended_metadata_triples` keeps DCAT structural assertions (type + distribution) separate from HealthDCAT-AP domain metadata.

---

## Blank Nodes and Nested Metadata (Cycle 5)

### Q: How are compound RDF blank node structures (retentionPeriod, contactPoint, legalBasis) represented in SEEK?

SEEK already has a first-class model for nested metadata: `ExtendedMetadataAttribute#linked_extended_metadata_type` links to a child `ExtendedMetadataType` whose attributes map to the blank node's sub-properties.

For example, a `retentionPeriod` field is modelled as an `ExtendedMetadataAttribute` with:
- `pid: "http://healthdataportal.eu/ns/health#retentionPeriod"`
- `sample_attribute_type.base_type: "LinkedExtendedMetadata"`
- `linked_extended_metadata_type` → an EMT named "PeriodOfTime" with `startDate` and `endDate` attributes

When the emitter encounters this attribute, it emits:

```turtle
<dataset/123>
    healthdcatap:retentionPeriod [
        a dct:PeriodOfTime ;
        dcat:startDate "2020-01-01" ;
        dcat:endDate   "2025-12-31"
    ] .
```

This reuses SEEK's existing `linked_extended_metadata_type` mechanism — no separate `HealthDcatBuilder` class is needed. Any attribute with a linked EMT automatically produces a blank node.

---

### Q: What determines the `rdf:type` of a blank node?

`ExtendedMetadataEmitter` has a `BLANK_NODE_TYPE_MAP` constant that maps predicate URIs to blank node types:

| Predicate | Blank node `rdf:type` |
|---|---|
| `dct:temporal` | `dct:PeriodOfTime` |
| `healthdcatap:retentionPeriod` | `dct:PeriodOfTime` |
| `dcat:contactPoint` | `vcard:Kind` |
| `dpv:hasLegalBasis` | `dpv:LegalBasis` |
| `dpv:hasPurpose` | `dpv:Purpose` |
| `healthdcatap:hdab` | `foaf:Agent` |
| (unknown) | no `rdf:type` emitted |

For predicates not in the map, the blank node is emitted without a type — the blank node's properties are still emitted, allowing the consuming system to infer the type from the predicate context.

---

### Q: Why is DPV (Data Privacy Vocabulary) not in the rdf-vocab gem?

DPV (`https://w3id.org/dpv#`) is a W3C standard vocabulary for privacy and data protection, but it is not included in `rdf-vocab 3.3.2` (the installed gem version). It must be defined manually using `RDF::Vocabulary`, the same pattern used for `HDCATVocab` and `SEEKHVocab`:

```ruby
class DPVVocab < RDF::Vocabulary('https://w3id.org/dpv#')
  property :hasPersonalData
  property :hasLegalBasis
  property :hasPurpose
  property :LegalBasis
  property :Purpose
end
```

The `dpv:` prefix is registered in `ns_prefixes` and the file is required in `config/initializers/seek_rdf.rb` before the emitter, so `DPVVocab` is available at class definition time.

---

## Serialization & Format Wiring (Cycle 6)

### Q: Why doesn't the HTTP-level prefix test assert `@prefix healthdcatap:` in the Turtle response for a plain DataFile?

`RDF::Writer` only emits namespace declarations for prefixes that are actually used in the graph. A plain `DataFile` (no HealthDCAT extended metadata) produces only `dcat:Dataset` and `dcat:Distribution` triples — it uses `dcat:` and `dcterms:` but not `healthdcatap:`, `seekh:`, or `dpv:`. The test was split into two assertions:

1. **HTTP body**: asserts only `@prefix dcat:` and `@prefix dcterms:` — the two prefixes guaranteed for any DataFile with a `ContentBlob`.
2. **`data_file.ns_prefixes`**: asserts that all five prefixes (`healthdcatap`, `seekh`, `dpv`, `dcat`, `dcterms`) are registered in the Ruby hash. This verifies the vocabulary is wired up without requiring the prefixes to be emitted in every Turtle response.

### Q: Why does the JSON-LD assertion use `include?('Dataset')` rather than an exact IRI match?

JSON-LD compact form shortens IRIs using the `@context`. The serializer compacts `http://www.w3.org/ns/dcat#Dataset` to either `"dcat:Dataset"` (prefixed form) or just `"Dataset"` (term form), depending on how the context is built. Rather than hardcoding the exact compact form, the test checks that `"Dataset"` appears anywhere in the `@type` array — robust across context variations.

### Q: What bug was fixed in `emit_blank_node` in Cycle 6?

The original guard clause was:

```ruby
return unless data.is_a?(Seek::JSONMetadata::Data)
```

This worked for in-memory test objects built with `ExtendedMetadata#set_attribute_value`, which passes values through `LinkedExtendedMetadataAttributeHandler#convert` and wraps them in `Seek::JSONMetadata::Data`. But when data is loaded from the database and then accessed, `get_attribute_value` can return a plain `Hash` or `HashWithIndifferentAccess` rather than a `Seek::JSONMetadata::Data` instance. The fix:

```ruby
data = data.data if data.respond_to?(:data)
data = data.to_h if data.is_a?(Seek::JSONMetadata::Data)
return unless data.is_a?(Hash) && data.any?
```

This unwraps any wrapper object, converts `Seek::JSONMetadata::Data` to a plain Hash, and then accepts any non-empty Hash — covering all return forms of `get_attribute_value` regardless of whether the record is new or DB-loaded.

---

## SHACL Validation Shapes (Cycle 7)

### Q: What is `public/vocab/seek-healthdcat-shapes.ttl` and how is it used?

It is a [SHACL](https://www.w3.org/TR/shacl/) shapes document that defines machine-readable constraints for the SEEK-HealthDCAT-AP profile. It contains two `sh:NodeShape` definitions:

- **`<#DatasetShape>`** — targets `dcat:Dataset`; 17 property constraints covering mandatory DCAT-AP fields (`dct:title`, `healthdcatap:healthCategory`) and optional HealthDCAT-AP fields
- **`<#DistributionShape>`** — targets `dcat:Distribution`; 4 property constraints (`dcat:accessURL` is a Violation, others are Warnings)

The file is served statically at `/vocab/seek-healthdcat-shapes.ttl`. Two rake tasks use it:

```bash
bundle exec rake rdf:validate[path/to/data.ttl]    # single file
bundle exec rake rdf:validate_fixtures              # all DataFiles in DB
```

`rdf:validate_fixtures` iterates every `DataFile` that supports RDF (`rdf_supported?`), generates Turtle, validates, and exits non-zero only on `sh:Violation` results — making it safe to add to CI.

### Q: Why are `healthdcatap:healthCategory` and `dcat:accessURL` `sh:Violation` while everything else is `sh:Warning`?

These two properties are considered mandatory under the SEEK-HealthDCAT-AP profile:

- `healthdcatap:healthCategory` is mandatory in HealthDCAT-AP Release 6 — without it, the dataset is not meaningfully classified in a health domain.
- `dcat:accessURL` is mandatory in DCAT-AP 3.0 for every `dcat:Distribution` — a distribution with no access URL is unreachable.

All other properties (`dct:license`, age ranges, `dpv:hasPersonalData`, etc.) are recommended or optional, so their absence produces Warnings rather than Violations. The `rdf:validate_fixtures` task only exits non-zero on Violations, so Warning-level gaps don't block CI.

---

## Seed Data & Example Output (Cycle 8)

### Q: What does the COVID-19 Patient Registry seed demonstrate?

`db/seeds/extended_metadata_drafts/healthdcat_covid19_example.seeds.rb` is a concrete end-to-end example of a HealthDCAT-AP dataset in SEEK. It creates:

1. **Two `ExtendedMetadataType` records**:
   - *HealthDCAT Retention Period* (`supported_type: 'ExtendedMetadata'`) — inner type for the blank node, with `dcat:startDate` and `dcat:endDate` attributes
   - *HealthDCAT-AP Health Dataset* (`supported_type: 'DataFile'`) — outer type with 9 attributes covering mandatory and optional HealthDCAT-AP properties

2. **A full ISA hierarchy**: Investigation → Study → Assay

3. **A `DataFile`** named "COVID-19 Patient Registry" with all HealthDCAT-AP fields populated, demonstrating:
   - IRI values (`healthCategory`, `personal_data_categories`, `access_rights`)
   - Plain literal (`population_coverage`)
   - Integer values (`min_typical_age`, `max_typical_age`, `number_of_records`)
   - Boolean value (`trusted_data_holder`)
   - Nested blank node (`retention_period` → `dct:PeriodOfTime`)

Run with: `bundle exec rake db:seed:extended_metadata_drafts:healthdcat_covid19_example`

### Q: Why do integer and boolean values appear as plain string literals in `docs/examples/covid19_registry.ttl`?

The seed's `int_type` and `boolean_type` `SampleAttributeType` records do not have `rdf_value_type` or `rdf_datatype` set. `RdfMapping` treats `rdf_value_type: nil` as `"literal"` and emits plain `RDF::Literal` values. So `18` becomes `"18"` not `"18"^^xsd:integer`.

The SHACL shapes flag this as `sh:Warning` (not `sh:Violation`) for age and count fields, so `rdf:validate_fixtures` still passes. To fix, update the relevant `SampleAttributeType` records to set `rdf_value_type: 'typed_literal'` and `rdf_datatype: 'http://www.w3.org/2001/XMLSchema#integer'` (for integers) or `xsd:boolean` (for booleans).

### Q: What does `rake rdf:generate_examples` do?

It finds the "COVID-19 Patient Registry" `DataFile` in the database (seeded by `healthdcat_covid19_example.seeds.rb`), calls `to_rdf` and `to_json_ld`, and writes the output to `docs/examples/covid19_registry.ttl` and `docs/examples/covid19_registry.jsonld`. These files serve as human-readable reference output and can be updated whenever the RDF pipeline changes.

### Q: What does `RdfHealthdcatExampleTest` test, and why is it in `test/integration/rdf/`?

It tests the full RDF generation pipeline for a HealthDCAT-AP `DataFile`, building the dataset in memory (not via HTTP) and calling `df.to_rdf` directly. The 9 tests assert:

| Test | What it checks |
|---|---|
| `emits dcat:Dataset type triple` | DCAT type assertion from `DcatEmitter` |
| `emits healthCategory as IRI` | `rdf_value_type: 'iri'` path in `RdfMapping` |
| `emits populationCoverage as literal` | Plain literal path |
| `emits dpv:hasPersonalData as IRI` | DPV namespace IRI value |
| `emits dct:accessRights as IRI` | DCTERMS IRI value |
| `emits retentionPeriod as blank node` | `emit_blank_node` with nested dates |
| `emits jerm type triple alongside dcat:Dataset` | Backwards-compatible JERM triple still present |
| `turtle output includes healthdcatap prefix declaration` | Prefix emitted when namespace is used |
| `json-ld output contains healthCategory` | JSON-LD serialisation path |

It lives in `test/integration/rdf/` because it exercises multiple layers (model + emitter + serializer) together, not a single unit.

---

## Application Profile Documentation (Cycle 9)

### Q: What is `docs/seek_healthdcat_ap.md` for?

It is the human-readable specification of the SEEK-HealthDCAT-AP profile — the single source of truth for how SEEK maps its data model to DCAT/HealthDCAT-AP RDF. It covers:

- Namespace declarations (with the gem/file each vocab comes from)
- Class mapping table (SEEK entity → RDF types)
- Three property tables: always-emitted core fields, auto-emitted `dcat:Distribution`, and extended metadata HealthDCAT-AP fields
- Blank node structure examples for `retentionPeriod`, `hasLegalBasis`, `contactPoint`
- A worked Turtle example (the COVID-19 registry)
- Step-by-step guide for adding a new extended metadata type with correct `pid` and `rdf_value_type`

### Q: What is `public/vocab/seek-healthdcat-ap.jsonld` and how does it differ from the JSON-LD output of `to_json_ld`?

`public/vocab/seek-healthdcat-ap.jsonld` is a reusable **JSON-LD context document** — a static vocabulary file that declares the namespace prefixes and property types for the profile. Any consumer can reference it via `"@context": "https://seek.example.org/vocab/seek-healthdcat-ap.jsonld"` to correctly interpret SEEK's JSON-LD output.

`to_json_ld` in `rdf_generation.rb` produces per-resource JSON-LD serializations from the RDF graph. The context it embeds is generated from `ns_prefixes` (a Ruby hash), which covers namespace declarations but not `@type` annotations for individual properties. The vocab context file fills that gap for external consumers who want to interpret IRI-valued properties as `@id` references and numeric fields as typed literals.

### Q: Why does `seekh.ttl` declare the namespace as an OWL Ontology if there are no pre-defined terms?

`seekh:` terms are derived at RDF generation time from `ExtendedMetadataAttribute` titles via `parameterize`. There is no fixed vocabulary — the terms depend on what attributes exist in the database. Publishing the OWL Ontology declaration serves three purposes:

1. Makes the namespace URI dereferenceable (consumers that follow the URI get back something meaningful)
2. Declares `owl:versionInfo` and `rdfs:label` so the namespace is self-describing
3. Signals to consuming tools that this namespace is intentionally minimal/dynamic

If a `seekh:` term appears in a consumer's triple store, they can look up the namespace URI and see the `rdfs:comment` explaining that terms are generated from attribute titles.

### Q: Why does `/vocab/seekh` redirect to `/vocab/seekh.ttl` rather than doing content negotiation?

Content negotiation (returning different formats based on `Accept` header) requires a controller action and is more complex to implement and test. Since SEEK currently exports only Turtle (the `:rdf` MIME type maps to `text/turtle`), a simple 301 redirect to the static `.ttl` file is sufficient and zero-maintenance. Rails serves `public/vocab/seekh.ttl` as a static file; the route just makes `/vocab/seekh` dereferenceable. If JSON-LD or RDF/XML formats are needed for the vocab file in future, the redirect can be replaced with a controller action.

### Q: What is the `Obligation` column in the property tables (M / R / O)?

It follows the DCAT-AP convention:

| Code | Meaning | SHACL severity |
|---|---|---|
| **M** — Mandatory | Must be present | `sh:Violation` (test failure) |
| **R** — Recommended | Should be present | `sh:Warning` |
| **O** — Optional | May be present | `sh:Warning` |

Only `healthdcatap:healthCategory` and `dcat:accessURL` (on Distribution) are Mandatory in the SEEK-HealthDCAT-AP profile. All other HealthDCAT-AP fields are Optional or Recommended.

---

## Two JSON-LD Pipelines & the `/dcat` Endpoint (Cycle 9.5)

### Q: SEEK already has a `.jsonld` export — how does `to_json_ld` differ from it?

SEEK has two completely independent JSON-LD export pipelines that coexist:

| | Bioschemas pipeline | RDF-graph pipeline |
|---|---|---|
| **Method** | `to_schema_ld` → `Seek::BioSchema::Serializer` | `to_json_ld` → `JSON::LD::API.compact(to_rdf_graph)` |
| **`@context`** | `"https://schema.org"` | Custom hash of JERM / DCAT / HealthDCAT-AP namespaces |
| **`@type`** | `"Dataset"` (schema.org) | `["jerm:Data", "dcat:Dataset"]` |
| **Properties** | `name`, `description`, `creator`, `distribution` (DataDownload) | JERM + DCTERMS + HealthDCAT-AP extended metadata |
| **Public URL** | `GET /data_files/:id` with `Accept: application/ld+json` | None (before Cycle 9.5) |
| **Consumer** | Google Dataset Search, Bioschemas harvesters | DCAT-AP / HealthDCAT-AP catalogues |

The Bioschemas format is served by `format.jsonld { render body: asset_version.to_schema_ld }` in `lib/seek/assets_standard_controller_actions.rb`. The RDF-graph JSON-LD compacts the full JERM + DCAT + HealthDCAT-AP graph using `JSON::LD::API` and the `ns_prefixes` hash.

Neither pipeline is "the" JSON-LD — they serve different interoperability communities and must coexist.

### Q: Why doesn't content-negotiation on `application/ld+json` work for HealthDCAT-AP consumers?

`application/ld+json` is already registered as the `:jsonld` MIME type in SEEK and mapped to the Bioschemas pipeline. Changing this mapping would break Bioschemas harvesters (e.g. Google Dataset Search) that already rely on `Accept: application/ld+json` returning Schema.org content.

The W3C content negotiation by profile spec (`Accept-Profile` header) would allow the same MIME type to return different profiles, but Rails MIME matching ignores `Accept` header parameters — so `application/ld+json; profile="http://www.w3.org/ns/dcat"` is treated identically to `application/ld+json` and routes to the same Bioschemas handler.

### Q: What is the `/dcat` endpoint and which resources have it?

`GET /:resource_type/:id/dcat` is a dedicated endpoint that serves the DCAT-AP / HealthDCAT-AP representation of a SEEK resource. It responds to two formats:

| `Accept` header | Response |
|---|---|
| `text/turtle` (or `application/rdf`) | DCAT Turtle — calls `resource.to_rdf` |
| `application/ld+json` | DCAT JSON-LD — calls `resource.to_json_ld` |

The action lives in `Seek::AssetsStandardControllerActions` (shared module included by all asset controllers via `Seek::AssetsCommon`). The route is added to both the `:asset` concern (DataFile, Model, SOP, Workflow, Document, etc.) and the `:isa` concern (Assay, Investigation, Study).

**Example URLs:**
```
GET /data_files/123/dcat             Accept: text/turtle          → HealthDCAT-AP Turtle
GET /data_files/123/dcat             Accept: application/ld+json  → DCAT JSON-LD
GET /assays/456/dcat                 Accept: text/turtle          → DCAT Turtle for Assay
GET /investigations/789/dcat         Accept: application/ld+json  → DCAT JSON-LD for Investigation
```

The existing `GET /data_files/123` with `Accept: application/ld+json` continues to return the Bioschemas format unchanged.

### Q: Why add the `/dcat` route to the `:asset` and `:isa` concerns rather than just `data_files`?

`to_json_ld` is defined in `Seek::Rdf::RdfGeneration`, which is included in all RDF-capable SEEK models — DataFile, Assay, Study, Investigation, Model, SOP, Workflow, and others. The DCAT class map in `DcatEmitter` maps four SEEK types (DataFile, Assay → `dcat:Dataset`; Investigation, Study → `dcat:Resource`). Making the endpoint available on all `:asset` and `:isa` resources means consumers can explore the DCAT structure for any resource, not just DataFiles. Resources without a DCAT type assertion still return valid (though minimal) Turtle output.

The `:asset` concern covers content-blob assets (DataFile, Model, SOP, etc.). The `:isa` concern covers ISA hierarchy nodes (Assay, Investigation, Study). Together they include all DCAT-mapped SEEK types.
