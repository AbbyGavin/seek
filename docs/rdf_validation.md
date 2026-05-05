# SEEK HealthDCAT-AP RDF Validation

## Overview

SEEK uses [SHACL](https://www.w3.org/TR/shacl/) shapes to validate that RDF exported for health datasets conforms to the **SEEK-HealthDCAT-AP profile** (based on HealthDCAT-AP Release 6 and DCAT-AP 3.0).

The shapes file is located at:

```
public/vocab/seek-healthdcat-shapes.ttl
```

It is served statically at `/vocab/seek-healthdcat-shapes.ttl`.

---

## Shapes defined

### `<#DatasetShape>` — `dcat:Dataset`

Targets resources typed as `dcat:Dataset` (i.e. `DataFile` and `Assay` exports).

| Property | Obligation | Value type | Severity |
|---|---|---|---|
| `dct:title` | Mandatory | `xsd:string` | Violation |
| `dct:description` | Optional | `xsd:string` | Warning |
| `dct:license` | Recommended | IRI | Warning |
| `dct:accessRights` | Recommended | Any | Warning |
| `dcat:keyword` | Optional | `xsd:string` | Warning |
| `dcat:contactPoint` | Optional | `vcard:Kind` | Warning |
| `dcat:distribution` | Optional | `dcat:Distribution` | Warning |
| `healthdcatap:healthCategory` | **Mandatory** | IRI | **Violation** |
| `healthdcatap:populationCoverage` | Optional | `xsd:string` | Warning |
| `healthdcatap:minimumTypicalAge` | Optional | `xsd:integer` | Warning |
| `healthdcatap:maximumTypicalAge` | Optional | `xsd:integer` | Warning |
| `healthdcatap:numberOfUniqueIndividuals` | Optional | `xsd:nonNegativeInteger` | Warning |
| `healthdcatap:numberOfRecords` | Optional | `xsd:nonNegativeInteger` | Warning |
| `healthdcatap:trusteddataholder` | Optional | `xsd:boolean` | Warning |
| `healthdcatap:retentionPeriod` | Optional | `dct:PeriodOfTime` | Warning |
| `dpv:hasPersonalData` | Optional | IRI | Warning |
| `dpv:hasLegalBasis` | Optional | Any | Warning |

> **Note**: `healthdcatap:healthCategory` is mandatory per HealthDCAT-AP Release 6. Datasets without it will fail SHACL validation with a `sh:Violation`.

### `<#DistributionShape>` — `dcat:Distribution`

Targets resources typed as `dcat:Distribution` (auto-emitted by `DcatEmitter` when a `ContentBlob` is present).

| Property | Obligation | Value type | Severity |
|---|---|---|---|
| `dcat:accessURL` | **Mandatory** | IRI | **Violation** |
| `dcat:downloadURL` | Recommended | IRI | Warning |
| `dct:format` | Optional | Any | Warning |
| `dcat:byteSize` | Optional | `xsd:decimal` | Warning |

---

## Running validation

### Validate a single Turtle file

```bash
bundle exec rake rdf:validate[path/to/data.ttl]
```

Example — validate a live export:

```bash
# Export a DataFile to a temp file, then validate
bundle exec rails runner "File.write('/tmp/df1.ttl', DataFile.first.to_rdf)"
bundle exec rake rdf:validate[/tmp/df1.ttl]
```

### Validate all DataFiles in the database

```bash
bundle exec rake rdf:validate_fixtures
```

This iterates every `DataFile` with RDF support, generates Turtle, runs SHACL validation, and reports any **Violation**-level failures. Warnings are noted but do not cause a non-zero exit.

---

## Using in CI

Add this to your CI pipeline after test suite:

```yaml
- name: SHACL validation
  run: bundle exec rake rdf:validate_fixtures
```

---

## Adding new shapes

Edit `public/vocab/seek-healthdcat-shapes.ttl`. Follow the existing pattern:

```turtle
sh:property [
  sh:path <predicate-uri> ;
  sh:name "fieldName" ;
  sh:description "..." ;
  sh:minCount 0 ;        # 1 = mandatory
  sh:datatype xsd:string ; # or sh:nodeKind sh:IRI
  sh:severity sh:Warning ; # or sh:Violation
] ;
```

---

## Namespaces

| Prefix | URI |
|---|---|
| `dcat:` | `http://www.w3.org/ns/dcat#` |
| `dct:` | `http://purl.org/dc/terms/` |
| `healthdcatap:` | `http://healthdataportal.eu/ns/health#` |
| `dpv:` | `https://w3id.org/dpv#` |
| `seekh:` | `https://seek4science.org/vocab/seekh#` |
| `vcard:` | `http://www.w3.org/2006/vcard/ns#` |
| `xsd:` | `http://www.w3.org/2001/XMLSchema#` |
| `sh:` | `http://www.w3.org/ns/shacl#` |

