# SEEK-HealthDCAT-AP Application Profile

This document specifies the **SEEK-HealthDCAT-AP** profile — an extension of
[HealthDCAT-AP Release 6](https://healthdataeu.pages.code.europa.eu/healthdcat-ap/releases/release-6/)
and [DCAT-AP 3.0](https://semiceu.github.io/DCAT-AP/releases/3.0.0/) for research datasets
managed by FAIRDOM-SEEK. It describes how SEEK's RDF export maps to standard DCAT classes and
HealthDCAT-AP properties, and explains how to configure extended metadata types to produce
semantically correct Turtle output.

---

## Namespaces

| Prefix | URI | Defined in |
|---|---|---|
| `dcat:` | `http://www.w3.org/ns/dcat#` | W3C DCAT 3 (rdf-vocab gem) |
| `dct:` | `http://purl.org/dc/terms/` | Dublin Core Terms (rdf-vocab gem as `RDF::Vocab::DC`) |
| `healthdcatap:` | `http://healthdataportal.eu/ns/health#` | `lib/seek/rdf/vocabularies/health_dcat.rb` |
| `dpv:` | `https://w3id.org/dpv#` | `lib/seek/rdf/vocabularies/dpv.rb` |
| `seekh:` | `https://seek4science.org/vocab/seekh#` | `lib/seek/rdf/vocabularies/seek_health.rb` |
| `jerm:` | `http://jermontology.org/ontology/JERMOntology#` | SEEK JERM ontology |
| `foaf:` | `http://xmlns.com/foaf/0.1/` | FOAF |
| `vcard:` | `http://www.w3.org/2006/vcard/ns#` | W3C vCard |
| `xsd:` | `http://www.w3.org/2001/XMLSchema#` | XML Schema datatypes |

The JSON-LD context that declares all of these is published at `/vocab/seek-healthdcat-ap.jsonld`.

---

## Class mapping

| SEEK entity | RDF type(s) emitted | Emitted by |
|---|---|---|
| `DataFile` | `jerm:Data`, `dcat:Dataset` | `describe_type` + `DcatEmitter` |
| `DataFile` (non-empty blob) | also `dcat:Distribution` (blank node) | `DcatEmitter` |
| `Assay` | `jerm:Assay`, `dcat:Dataset` | `describe_type` + `DcatEmitter` |
| `Study` | `jerm:Study`, `dcat:Resource` | `describe_type` + `DcatEmitter` |
| `Investigation` | `jerm:Investigation`, `dcat:Resource` | `describe_type` + `DcatEmitter` |
| `Person` | `jerm:Person`, `foaf:Person` | `describe_type` |
| `Project` | `jerm:Project`, `foaf:Project` | `describe_type` |

---

## Properties — `dcat:Dataset` (DataFile / Assay)

### Always emitted — core SEEK fields

These come from `rdf_mappings.csv` (`generate_from_csv_definitions`) and are present for every
exported resource, regardless of extended metadata.

| Property | Obligation | Value type | Source in SEEK |
|---|---|---|---|
| `dct:title` | M | plain literal | `DataFile#title` |
| `dct:description` | R | plain literal | `DataFile#description` |
| `dct:created` | R | `xsd:dateTime` | `DataFile#created_at` |
| `dct:modified` | R | `xsd:dateTime` | `DataFile#updated_at` |
| `jerm:title` | — | plain literal | duplicate for JERM consumers |
| `jerm:description` | — | plain literal | duplicate for JERM consumers |
| `jerm:hasContributor` | — | IRI | `Person` who created the record |
| `sioc:has_owner` | — | IRI | same person as `jerm:hasContributor` |
| `jerm:seekID` | — | `xsd:anyURI` | canonical URL of the resource |

### Auto-emitted for downloadable DataFiles — `dcat:Distribution`

Emitted by `DcatEmitter` when the `DataFile` has a non-empty `ContentBlob`.

| Property | Obligation | Value type | Notes |
|---|---|---|---|
| `dcat:distribution` | R | blank node | links Dataset to its Distribution |
| ↳ `rdf:type` | M | `dcat:Distribution` | on the blank node |
| ↳ `dcat:accessURL` | M | IRI | `{resource_uri}/download` |
| ↳ `dcat:downloadURL` | R | IRI | same as `accessURL` |
| ↳ `dcat:byteSize` | O | `xsd:decimal` | omitted if `file_size` is 0 |
| ↳ `dct:format` | O | plain literal | MIME type string, e.g. `"text/csv"` |

### Extended metadata fields — HealthDCAT-AP

These are emitted only when the `DataFile` has an `ExtendedMetadata` record attached via
an `ExtendedMetadataType` whose attributes carry the listed `pid` values.

| Property | Obligation | Value type | `rdf_value_type` on SAT | Notes |
|---|---|---|---|---|
| `healthdcatap:healthCategory` | **M** | IRI | `iri` | **Mandatory per HealthDCAT-AP Release 6**; skos:Concept IRI from health-categories authority table |
| `healthdcatap:populationCoverage` | R | plain/lang literal | `lang_literal` | Human-readable description of covered population |
| `healthdcatap:minTypicalAge` | O | `xsd:integer` | `typed_literal` | `rdf_datatype: xsd:integer` |
| `healthdcatap:maxTypicalAge` | O | `xsd:integer` | `typed_literal` | `rdf_datatype: xsd:integer` |
| `healthdcatap:numberOfRecords` | O | `xsd:nonNegativeInteger` | `typed_literal` | `rdf_datatype: xsd:nonNegativeInteger` |
| `healthdcatap:numberOfUniqueIndividuals` | O | `xsd:nonNegativeInteger` | `typed_literal` | |
| `healthdcatap:trusteddataholder` | O | `xsd:boolean` | `typed_literal` | `rdf_datatype: xsd:boolean` |
| `healthdcatap:retentionPeriod` | O | `dct:PeriodOfTime` blank node | Linked EMT | Inner EMT attrs: `dcat:startDate`, `dcat:endDate` as string literals |
| `healthdcatap:hasCodingSystem` | O | IRI | `iri` | IRI of a `dct:Standard` (e.g. Wikidata ICD-10 entry) |
| `healthdcatap:hasCodeValues` | O | lang literal | `lang_literal` | E.g. `"U07.1"@en` |
| `healthdcatap:healthTheme` | O | IRI | `iri` | skos:Concept from health-theme authority table |
| `healthdcatap:publisherNote` | O | lang literal | `lang_literal` | |
| `healthdcatap:publisherType` | O | IRI | `iri` | From publisher-type authority table |
| `dpv:hasPersonalData` | O | IRI | `iri` | `dpv-pd:` namespace IRIs, e.g. `dpv-pd:HealthRecord` |
| `dpv:hasLegalBasis` | O | `dpv:LegalBasis` blank node | Linked EMT | Sub-props: `dct:description`, `dct:source` |
| `dpv:hasPurpose` | O | `dpv:Purpose` blank node | Linked EMT | Sub-props: `dct:description` |
| `dct:accessRights` | R | IRI | `iri` | EU Publications Office access-right vocabulary |

**Obligation key**: M = Mandatory (SHACL Violation if missing), R = Recommended (SHACL Warning), O = Optional

---

## Blank node structures

Some properties map to compound RDF structures (blank nodes). In SEEK these are modelled as
**linked extended metadata types** (`ExtendedMetadataAttribute#linked_extended_metadata_type`).

### `healthdcatap:retentionPeriod` → `dct:PeriodOfTime`

```turtle
<dataset>
    healthdcatap:retentionPeriod [
        a dct:PeriodOfTime ;
        dcat:startDate "2020-03-01" ;
        dcat:endDate   "2030-12-31"
    ] .
```

Inner EMT attributes: `pid: "http://www.w3.org/ns/dcat#startDate"` and `pid: "http://www.w3.org/ns/dcat#endDate"`.

### `dpv:hasLegalBasis` → `dpv:LegalBasis`

```turtle
<dataset>
    dpv:hasLegalBasis [
        a dpv:LegalBasis ;
        dct:description "Art. 9(2)(j) GDPR — scientific research"
    ] .
```

### `dcat:contactPoint` → `vcard:Kind`

```turtle
<dataset>
    dcat:contactPoint [
        a vcard:Kind ;
        vcard:fn "Data Access Office" ;
        vcard:hasEmail <mailto:dao@example.org>
    ] .
```

---

## Worked example — COVID-19 Patient Registry

The following Turtle output is produced by SEEK for a `DataFile` with the
HealthDCAT-AP extended metadata type applied (see `docs/examples/covid19_registry.ttl`):

```turtle
@prefix dcat:         <http://www.w3.org/ns/dcat#> .
@prefix dcterms:      <http://purl.org/dc/terms/> .
@prefix healthdcatap: <http://healthdataportal.eu/ns/health#> .
@prefix dpv:          <https://w3id.org/dpv#> .
@prefix jerm:         <http://jermontology.org/ontology/JERMOntology#> .

<http://seek.example.org/data_files/1>
    a jerm:Data, dcat:Dataset ;

    dcterms:title       "COVID-19 Patient Registry" ;
    dcterms:description "Clinical data of hospitalised COVID-19 patients." ;

    healthdcatap:healthCategory
        <http://13.81.34.152:1101/resource/authority/healthcategories/INFECTIOUS_DISEASE> ;
    healthdcatap:populationCoverage
        "Adult hospitalised COVID-19 patients aged 18-65" ;
    healthdcatap:minimumTypicalAge "18" ;
    healthdcatap:maximumTypicalAge "65" ;
    healthdcatap:trusteddataholder "true" ;
    healthdcatap:retentionPeriod [
        a dcterms:PeriodOfTime ;
        dcat:startDate "2020-03-01" ;
        dcat:endDate   "2030-12-31"
    ] ;

    dpv:hasPersonalData <https://w3id.org/dpv/dpv-pd#HealthRecord> ;
    dcterms:accessRights
        <http://publications.europa.eu/resource/authority/access-right/RESTRICTED> .
```

The live example file (generated from the COVID-19 seed) is at `docs/examples/covid19_registry.ttl`.
Regenerate with: `bundle exec rake rdf:generate_examples`

---

## SHACL validation

Machine-readable constraints are in `public/vocab/seek-healthdcat-shapes.ttl`, served at
`/vocab/seek-healthdcat-shapes.ttl`. Validate a Turtle file:

```bash
bundle exec rake rdf:validate[path/to/data.ttl]
bundle exec rake rdf:validate_fixtures   # all DataFiles in DB
```

See `docs/rdf_validation.md` for full details.

---

## How to add a new HealthDCAT-AP extended metadata type

### 1. Create the `ExtendedMetadataType`

```ruby
emt = ExtendedMetadataType.new(
  title: 'My Health Dataset',
  supported_type: 'DataFile'
)
```

### 2. Add attributes with the correct `pid` and `rdf_value_type`

For each field, create an `ExtendedMetadataAttribute` with:
- `pid` — the RDF predicate URI (e.g. `"http://healthdataportal.eu/ns/health#healthCategory"`)
- `sample_attribute_type` — a `SampleAttributeType` with the correct `rdf_value_type` and `rdf_datatype`

```ruby
# IRI-valued field (e.g. health category)
iri_sat = SampleAttributeType.find_or_create_by!(title: 'URI - IRI') do |sat|
  sat.base_type    = Seek::Samples::BaseType::STRING
  sat.regexp       = '.*'
  sat.rdf_value_type = 'iri'
end

emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(
  title: 'health_category',
  label: 'Health Category',
  pid:   'http://healthdataportal.eu/ns/health#healthCategory',
  sample_attribute_type: iri_sat
)

# Typed literal (integer)
int_sat = SampleAttributeType.find_or_create_by!(title: 'Integer - typed RDF') do |sat|
  sat.base_type    = Seek::Samples::BaseType::INTEGER
  sat.rdf_value_type = 'typed_literal'
  sat.rdf_datatype   = 'http://www.w3.org/2001/XMLSchema#integer'
end

emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(
  title: 'min_age',
  pid:   'http://healthdataportal.eu/ns/health#minTypicalAge',
  sample_attribute_type: int_sat
)
```

### 3. For blank node fields, create an inner `ExtendedMetadataType`

```ruby
period_emt = ExtendedMetadataType.new(
  title: 'Period Of Time',
  supported_type: 'ExtendedMetadata'
)
period_emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(
  title: 'start_date',
  pid:   'http://www.w3.org/ns/dcat#startDate',
  sample_attribute_type: string_sat
)
period_emt.save!

linked_sat = SampleAttributeType.find_or_initialize_by(title: 'Linked Extended Metadata')
linked_sat.update(base_type: Seek::Samples::BaseType::LINKED_EXTENDED_METADATA)

emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(
  title: 'retention_period',
  pid:   'http://healthdataportal.eu/ns/health#retentionPeriod',
  sample_attribute_type: linked_sat,
  linked_extended_metadata_type: period_emt
)
```

The `ExtendedMetadataEmitter` will automatically detect the linked type and emit a blank node with the
inner attributes as sub-properties. The blank node's `rdf:type` is looked up from `BLANK_NODE_TYPE_MAP`
in the emitter.

### 4. Verify the output

```ruby
df = DataFile.find(id)
puts df.to_rdf
```

Check that:
- IRI fields appear as `<uri>` not `"string"`
- Typed literals appear as `"value"^^xsd:integer`
- Blank nodes appear with the correct `rdf:type` and sub-properties

---

## `seekh:` extension namespace

`seekh:` (`https://seek4science.org/vocab/seekh#`) is the SEEK-specific extension namespace.
It is used **only as a fallback** when an `ExtendedMetadataAttribute` has no `pid` set. The term
is auto-derived from the attribute title via `parameterize(separator: '_')`.

The namespace is declared as an OWL ontology at `public/vocab/seekh.ttl`, served at `/vocab/seekh`
(redirects to `/vocab/seekh.ttl`). Terms in this namespace should be treated as unstable — assign
a proper `pid` to any attribute you want stable RDF output for.
