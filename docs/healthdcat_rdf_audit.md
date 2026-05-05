# HealthDCAT-AP RDF Audit — Cycle 0

## 1. Full call chain (GET /data_files/1, Accept: text/turtle)

```
DataFilesController#show
  (inherits) Seek::AssetsStandardControllerActions#show
    respond_to do |format|
      format.rdf { render template: 'rdf/show' }   # lib/seek/assets_standard_controller_actions.rb:20
    end

app/views/rdf/show.rdf.erb
  <%= asset_rdf.html_safe -%>

app/helpers/rdf_helper.rb#asset_rdf
  resource_for_controller.to_rdf                   # calls to_rdf on the DataFile instance

lib/seek/rdf/rdf_generation.rb (module, included in DataFile)
  #to_rdf
    rdf_graph = to_rdf_graph
    RDF::Writer.for(:ttl).buffer(prefixes: ns_prefixes) { |w| rdf_graph.each_statement { |s| w << s } }

  #to_rdf_graph  ← four sequential steps
    1. describe_type(rdf_graph)            # emits rdf:type triple via JERMVocab
    2. generate_from_csv_definitions(...)  # CSV-driven bulk triples (lib/seek/rdf/csv_mappings_handling.rb)
    3. additional_triples(...)             # model-specific extras (SBML format for Model)
    4. extended_metadata_triples(...)      # pid-based emitter for ExtendedMetadata fields
    [5. sample_metadata_triples(...)]      # Sample only
```

**MIME type registration** (`config/initializers/mime_types.rb:10`):
```ruby
Mime::Type.register "text/turtle", :rdf, ["application/rdf", "application/x-turtle"]
```
`:rdf` format = Turtle. There is no `:rdfxml` registered. `application/ld+json` → `:jsonld` is separate.

---

## 2. Files that will need modification

### Modify (existing files)
| File | Change needed |
|---|---|
| `lib/seek/rdf/rdf_generation.rb` | Add `dcat_type_triples` step to `to_rdf_graph`; update `extended_metadata_triples` to delegate to new emitter; extend `ns_prefixes` with `dcat`, `healthdcatap`, `seekh` (**done in Cycle 1**) |
| `config/initializers/seek_rdf.rb` | Require new vocabulary files (**done in Cycle 1**) |
| `app/models/extended_metadata_attribute.rb` | Accessors for new `rdf_value_type` / `rdf_datatype` columns after migration (Cycle 2) |
| `test/unit/rdf_generation_test.rb` | Extend with DCAT type triple assertions (Cycle 4) |
| `test/integration/rdf_response_test.rb` | Extend with HealthDCAT-AP content assertions (Cycle 6) |

### Create (new files)
| File | Purpose | Cycle |
|---|---|---|
| `lib/seek/rdf/vocabularies/health_dcat.rb` | `HDCATVocab` — HealthDCAT-AP Release 6 properties | **Done (Cycle 1)** |
| `lib/seek/rdf/vocabularies/seek_health.rb` | `SEEKHVocab` — SEEK extension namespace | **Done (Cycle 1)** |
| `test/unit/rdf/vocabularies_test.rb` | Vocabulary IRI and ns_prefixes tests | **Done (Cycle 1)** |
| `lib/seek/rdf/rdf_mapping.rb` | Value object: predicate + value-type + datatype → `RDF::Term` | Cycle 2 |
| `lib/seek/rdf/extended_metadata_emitter.rb` | Replaces inline `extended_metadata_triples` logic | Cycle 3 |
| `lib/seek/rdf/health_dcat_builder.rb` | Complex blank-node builders (retentionPeriod, hdab, analytics) | Cycle 5 |
| `db/migrate/*_add_rdf_value_type_to_extended_metadata_attributes.rb` | Migration for `rdf_value_type`, `rdf_datatype` columns | Cycle 2 |
| `db/seeds/extended_metadata_drafts/healthdcat_covid19_example.seeds.rb` | COVID-19 registry example seed | Cycle 8 |
| `public/vocab/seek-healthdcat-shapes.ttl` | SHACL shapes | Cycle 7 |
| `public/vocab/seek-healthdcat-ap.jsonld` | JSON-LD context | Cycle 9 |
| `public/vocab/seekh.ttl` | `seekh:` namespace definition | Cycle 9 |
| `lib/tasks/rdf_validate.rake` | SHACL validation task | Cycle 7 |
| `lib/tasks/rdf_examples.rake` | Example generation task | Cycle 8 |
| `docs/examples/covid19_registry.ttl` | Example Turtle output | Cycle 8 |
| `docs/examples/covid19_registry.jsonld` | Example JSON-LD output | Cycle 8 |
| `docs/seek_healthdcat_ap.md` | Application profile document | Cycle 9 |

### Do NOT modify
| File | Reason |
|---|---|
| `lib/seek/rdf/rdf_mappings.csv` | Backwards-compat; new DCAT triples are additive |
| `lib/seek/rdf/jerm_vocab.rb` | JERM vocabulary unchanged |
| `config/initializers/mime_types.rb` | `:rdf` = Turtle already; only touch if adding `:rdfxml` |

---

## 3. Gem versions (from Gemfile.lock)

| Gem | Version |
|---|---|
| `linkeddata` | 3.3.3 |
| `json-ld` | 3.3.2 |
| `json-ld-preloaded` | 3.3.1 |
| `rdf-turtle` | 3.3.1 |
| `rdf-vocab` | 3.3.2 |

---

## 4. CRITICAL: DC vs DCTERMS in rdf-vocab 3.3.2

**This contradicts the original plan and must be read carefully.**

In rdf-vocab 3.3.2 (the installed version):

| Constant | URI | Meaning |
|---|---|---|
| `RDF::Vocab::DC` | `http://purl.org/dc/terms/` | Dublin Core **Terms** (DCTERMS) |
| `RDF::Vocab::DC11` | `http://purl.org/dc/elements/1.1/` | Dublin Core Elements 1.1 |
| `RDF::Vocab::DCTERMS` | **does not exist** — raises `NameError` | — |

Verified by running in the project bundle:
```
bundle exec ruby -e "require 'rdf/vocab'; puts RDF::Vocab::DC.to_uri; puts RDF::Vocab::DC11.to_uri"
# → http://purl.org/dc/terms/
# → http://purl.org/dc/elements/1.1/
```

**Consequences for this project**:

- `rdf_mappings.csv` uses `RDF::Vocab::DC.created`, `RDF::Vocab::DC.title`, etc. — these resolve to `http://purl.org/dc/terms/created`, `http://purl.org/dc/terms/title`. They are **already DCTERMS URIs**, not DC Elements 1.1.
- `ns_prefixes` labels the prefix `'dcterms'` and points to `RDF::Vocab::DC.to_uri` = `http://purl.org/dc/terms/`. Correct.
- The correct alias for new code: `DCTERMS = RDF::Vocab::DC` (not `RDF::Vocab::DCTERMS`).
- If DC Elements 1.1 is ever needed explicitly, use `RDF::Vocab::DC11`.

---

## 5. HealthDCAT-AP vocabulary — verified property list (Cycle 1)

**Spec**: https://healthdataeu.pages.code.europa.eu/healthdcat-ap/releases/release-6/
**Namespace**: `http://healthdataportal.eu/ns/health#` (prefix: `healthdcatap`)
**Source**: official TTL example files at `public/releases/release-6/html/examples/` in the repository

All properties below are verified against their individual example `.ttl` files.

### healthdcatap: properties (http://healthdataportal.eu/ns/health#)

| Property | Value type | Example file |
|---|---|---|
| `healthCategory` | IRI (`skos:Concept` from health-categories authority table) | `healthdcataphealthCategory.ttl` |
| `hdab` | `foaf:Agent` blank node with `cv:contactPoint` | `healthdcataphdab.ttl` |
| `healthTheme` | IRI (`skos:Concept` from health-theme authority table) | `healthdcataphealththeme.ttl` |
| `populationCoverage` | Lang-tagged literal | `healthdcatappopulationCoverage.ttl` |
| `retentionPeriod` | `dct:PeriodOfTime` blank node (`dcat:startDate` / `dcat:endDate`) | `healthdcatapretentionperiod.ttl` |
| `minTypicalAge` | `xsd:integer` | `healthdcatapminTypicalAge.ttl` |
| `maxTypicalAge` | `xsd:integer` | `healthdcatapmaxTypicalAge.ttl` |
| `numberOfRecords` | `xsd:nonNegativeInteger` | `healthdcatapnumberOfRecords.ttl` |
| `numberOfUniqueIndividuals` | `xsd:nonNegativeInteger` | `healthdcatapnumberOfUniqueIndividuals.ttl` |
| `hasCodingSystem` | IRI of `dct:Standard` | `healthdcataphasCodingSystem.ttl` |
| `hasCodeValues` | Lang-tagged literal (e.g. `"U07.1"@en`) | `healthdcataphasCodeValues.ttl` |
| `analytics` | `dcat:Distribution` blank node | `healthdcatapanalytics.ttl` |
| `publisherNote` | Lang-tagged literal | `healthdcatappublishernote.ttl` |
| `publisherType` | IRI from publisher-type authority table | `healthdcatappublishertype.ttl` |
| `trusteddataholder` | `xsd:boolean` | `healthdcataptrusteddataholder.ttl` |

### Privacy properties — DPV vocabulary (https://w3id.org/dpv#)

These are **not** `healthdcatap:` properties. The spec delegates them to W3C DPV.

| Property | Value type | Example file |
|---|---|---|
| `dpv:hasPersonalData` | IRI from `dpv-pd:` namespace (e.g. `dpv-pd:HealthRecord`) | `dpvhasPersonalData.ttl` / `healthdcatappersonalData.ttl` |
| `dpv:hasLegalBasis` | `dpv:LegalBasis` blank node with `dct:description` + `dct:source` | `dpvhasLegalBasis.ttl` / `healthdcataplegalBasis.ttl` |
| `dpv:hasPurpose` | `dpv:Purpose` blank node with `dct:description` | `dpvhasPurpose.ttl` |

---

## 6. Extended metadata storage

- `ExtendedMetadataType` — named schema, `supported_type` (model class or `'ExtendedMetadata'` for inner/nested), has many `extended_metadata_attributes`.
- `ExtendedMetadataAttribute` — one field: `title`, `pid` (predicate URI string), `sample_attribute_type`, optionally `linked_extended_metadata_type` for nested schemas. New columns `rdf_value_type` / `rdf_datatype` added in Cycle 2.
- `ExtendedMetadata` — one instance attached polymorphically to an asset via `item_type/item_id`. Values stored as JSON in `json_metadata`. Retrieved via `get_attribute_value(attribute)`.
- `HasExtendedMetadata` concern — included in asset models; adds `has_one :extended_metadata` association.

**Current `extended_metadata_triples` limitation** (line 80 of `rdf_generation.rb`):
```ruby
rdf_graph << [resource, RDF::URI(attribute.pid), RDF::Literal(extended_metadata.get_attribute_value(attribute))]
```
Always emits a plain `RDF::Literal`. No typed literals, no IRI values, no language tags, no nested blank nodes. This is what Cycles 2–5 replace.

---

## 7. Existing RDF tests

| File | Type | What it tests |
|---|---|---|
| `test/unit/rdf_generation_test.rb` | Unit | RightField RDF, storage paths, file save/delete, Turtle validity |
| `test/unit/rdf/vocabularies_test.rb` | Unit | HDCATVocab/SEEKHVocab IRI resolution, ns_prefixes (**added Cycle 1**) |
| `test/integration/rdf_response_test.rb` | Integration (HTTP) | MIME type negotiation for `text/turtle`, `application/rdf`, `application/x-turtle`; statement count round-trip |
| `test/integration/rdf_triple_store_test.rb` | Integration | Virtuoso triple store push/query |

No existing tests assert specific predicate/object values (e.g. `dc:title` content). New cycles add those.

---

## 8. Current state vs planned changes summary

**Current state**: SEEK emits JERM-typed Turtle for 14 resource types. Triples come from:
1. One `rdf:type` triple (JERM class)
2. CSV-driven bulk triples (DC Terms, JERM, FOAF, SIOC)
3. Model-specific extras (`jerm:hasFormat` for SBML models)
4. Plain-literal extended metadata triples (when `pid` set)

`ns_prefixes` now has 12 entries including `dcat:`, `healthdcatap:`, `seekh:` (added Cycle 1). No HealthDCAT-AP triples are emitted yet.

**After all cycles**: A `DataFile` with health extended metadata emits:
- All existing JERM/DC triples unchanged (backwards compat)
- `rdf:type dcat:Dataset` in addition to `jerm:Data`
- `dcat:Distribution` blank node with download URL, byte size, format
- Extended metadata fields as typed literals or IRIs (from `rdf_value_type`/`rdf_datatype`)
- `healthdcatap:healthCategory`, `healthdcatap:populationCoverage`, `healthdcatap:retentionPeriod` (as `dct:PeriodOfTime` blank node), `healthdcatap:trusteddataholder`, etc.
- `dpv:hasPersonalData`, `dpv:hasLegalBasis`, `dpv:hasPurpose` for privacy/legal fields
- `dcat:contactPoint` and `dct:temporal` as structured blank nodes
- `seekh:*` fallback for unmapped fields

---

## 9. Cycle completion status

| Cycle | Description | Status |
|---|---|---|
| 0 | Repository audit | Done |
| 1 | Vocabulary definitions & namespace registration | Done |
| 2 | Extended metadata — RDF mapping configuration | Pending |
| 3 | Enhanced extended metadata emitter | Pending |
| 4 | DCAT type assertions | Pending |
| 5 | HealthDCAT-AP specific builders | Pending |
| 6 | Serialization and format wiring | Pending |
| 7 | SHACL validation shapes | Pending |
| 8 | Seed data & example output | Pending |
| 9 | Application profile documentation | Pending |
| 10 | Regression & backwards compatibility tests | Pending |
