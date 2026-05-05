# RDF Export: Extended Metadata Support

Branch: `support-nested-em-rdf-export` — relates to [#2557](https://github.com/seek4science/seek/issues/2557)

---

## What changed

### Problem

Before this branch, `extended_metadata_triples` in `lib/seek/rdf/rdf_generation.rb` only emitted flat, top-level attributes:

```ruby
# old code
attributes = extended_metadata.extended_metadata_type.extended_metadata_attributes
              .select { |at| at.pid.present? }
resource = rdf_resource
attributes.each do |attribute|
  rdf_graph << [resource, RDF::URI(attribute.pid),
                RDF::Literal(extended_metadata.get_attribute_value(attribute))]
end
```

Two bugs:
1. **Nested extended metadata was ignored.** `LinkedExtendedMetadata` and `LinkedExtendedMetadataMulti` attributes were emitted as plain string literals instead of blank nodes with their own triples.
2. **All scalar values were emitted as plain string literals** regardless of their actual base type. A `Date` attribute stored as `"2024-01-15"` appeared as `"2024-01-15"` (untyped string) rather than `"2024-01-15"^^xsd:date`.

### Solution

`extended_metadata_triples` now delegates to three private helpers:

```
emit_emt_attributes   — iterates attributes, skips those without a PID or with nil values
  └─ emit_emt_attribute  — dispatches on attribute type
       ├─ typed_rdf_literal          — scalar types → correctly typed XSD literal
       └─ append_emt_blank_node      — linked types → blank node + recursive emit_emt_attributes
```

#### `emit_emt_attributes`

```ruby
def emit_emt_attributes(rdf_graph, subject, emt_type, data)
  emt_type.extended_metadata_attributes.each do |attribute|
    next unless attribute.pid.present?
    value = data[attribute.accessor_name]
    next if value.nil?
    emit_emt_attribute(rdf_graph, subject, attribute, value)
  end
end
```

- `subject` is either the asset's RDF resource or a blank node (for nested calls).
- Attributes without a PID are silently skipped.
- Nil values (unset fields) produce no triple.

#### `emit_emt_attribute`

```ruby
def emit_emt_attribute(rdf_graph, subject, attribute, value)
  predicate = RDF::URI(attribute.pid)
  if attribute.linked_extended_metadata?
    append_emt_blank_node(rdf_graph, subject, predicate,
                          attribute.linked_extended_metadata_type, value)
  elsif attribute.linked_extended_metadata_multi?
    Array(value).each do |item|
      append_emt_blank_node(rdf_graph, subject, predicate,
                            attribute.linked_extended_metadata_type, item)
    end
  else
    rdf_graph << [subject, predicate, typed_rdf_literal(attribute, value)]
  end
end
```

#### `append_emt_blank_node`

```ruby
def append_emt_blank_node(rdf_graph, subject, predicate, nested_type, data)
  blank = RDF::Node.new
  rdf_graph << [subject, predicate, blank]
  emit_emt_attributes(rdf_graph, blank, nested_type, data)
end
```

Each `LinkedExtendedMetadata` attribute emits one blank node. `LinkedExtendedMetadataMulti` emits one blank node per array item. Both recurse into `emit_emt_attributes`, so arbitrarily deep nesting is supported.

#### `typed_rdf_literal`

```ruby
def typed_rdf_literal(attribute, value)
  case attribute.sample_attribute_type&.base_type
  when Seek::Samples::BaseType::DATE
    RDF::Literal(value.to_s, datatype: RDF::XSD.date)
  when Seek::Samples::BaseType::DATE_TIME
    RDF::Literal(value.to_s, datatype: RDF::XSD.dateTime)
  when Seek::Samples::BaseType::INTEGER
    RDF::Literal(value.to_i, datatype: RDF::XSD.integer)
  when Seek::Samples::BaseType::FLOAT
    RDF::Literal(value.to_f, datatype: RDF::XSD.double)
  when Seek::Samples::BaseType::BOOLEAN
    RDF::Literal(value, datatype: RDF::XSD.boolean)
  else
    RDF::Literal(value)   # String, Text, CV, etc. → plain literal
  end
end
```

`Date` and `DateTime` are passed as `.to_s` because they are stored as strings in the JSON metadata. All other typed values come back from JSON with their native Ruby type (Integer, Float, TrueClass/FalseClass).

#### Turtle serialization note

Turtle has built-in abbreviated syntax for three XSD types. A conforming parser treats these as fully typed:

| BaseType  | Turtle output | Equivalent explicit form          |
|-----------|---------------|-----------------------------------|
| Integer   | `42`          | `"42"^^xsd:integer`               |
| Float     | `3.14e0`      | `"3.14e0"^^xsd:double`            |
| Boolean   | `true`/`false`| `"true"^^xsd:boolean`             |
| Date      | `"2024-01-15"^^xsd:date` | *(no shorthand)*       |
| DateTime  | `"2024-01-15T12:00:00"^^xsd:dateTime` | *(no shorthand)* |

This is why dates look different from booleans and integers in the `.rdf` output even though all are correctly typed.

---

## Files changed

| File | Change |
|------|--------|
| `lib/seek/rdf/rdf_generation.rb` | Core fix: `emit_emt_attributes`, `emit_emt_attribute`, `typed_rdf_literal`, `append_emt_blank_node` |
| `test/unit/rdf_generation_test.rb` | Tests for nested single, nested multi, partial PID, flat literal, and all scalar XSD types |
| `test/factories/extended_metadata_types.rb` | New factories: `float_extended_metadata_attribute`, `text_extended_metadata_attribute`, `boolean_extended_metadata_attribute`, `date_extended_metadata_attribute`, `rdf_test_data_file_all_types_emt`, `rdf_test_data_file_date_emt` |
| `test/factories/sample_attribute_types.rb` | New factory: `date_sample_attribute_type` |
| `db/seeds/extended_metadata_drafts/study_nested_emt_rdf_example.seeds.rb` | Example Study EMT covering all scalar types + single nested + multi-nested |

---

## Seed: `study_nested_emt_rdf_example`

Run with:

```bash
bundle exec rake seek:seed:extended_metadata_draft[study_nested_emt_rdf_example]
```

Creates three EMTs:

| Title | Supported type | Purpose |
|-------|---------------|---------|
| `study_rdf_example_period` | `ExtendedMetadata` | Inner nested: `start_date` + `end_date` (both `xsd:date`) |
| `study_rdf_example_contact` | `ExtendedMetadata` | Inner nested: `name` + `email` (both string, used as multi-linked) |
| `study_rdf_example` | `Study` | Outer: one attribute per scalar type + `collection_period` (single linked) + `contact_persons` (multi-linked) |

The outer Study EMT attributes:

| Title | BaseType | PID | XSD output |
|-------|----------|-----|-----------|
| `study_label` | String | `schema:name` | plain literal |
| `study_abstract` | Text | `schema:abstract` | plain literal |
| `participant_count` | Integer | `schema:numberOfItems` | `xsd:integer` |
| `success_rate` | Float | `fairbd:successRate` | `xsd:double` |
| `randomized` | Boolean | `schema:isPartOf` | `xsd:boolean` |
| `registration_date` | Date | `schema:dateCreated` | `xsd:date` |
| `last_updated` | DateTime | `schema:dateModified` | `xsd:dateTime` |
| `collection_period` | LinkedExtendedMetadata | `schema:temporalCoverage` | blank node |
| `contact_persons` | LinkedExtendedMetadataMulti | `schema:contributor` | blank node per item |

---

## How RDF generation works overall

`to_rdf_graph` calls four steps in order:

```ruby
def to_rdf_graph
  rdf_graph = RDF::Graph.new
  rdf_graph = describe_type(rdf_graph)               # 1. rdf:type triple
  rdf_graph = generate_from_csv_definitions(rdf_graph) # 2. CSV mapping
  rdf_graph = additional_triples(rdf_graph)           # 3. hard-coded extras
  rdf_graph = extended_metadata_triples(rdf_graph)    # 4. dynamic EMT attributes
  rdf_graph
end
```

### Step 2: `rdf_mappings.csv`

`lib/seek/rdf/rdf_mappings.csv` is a declarative table of fixed JERM/Dublin Core triples
for all asset types. It is read by `CSVMappingsHandling#generate_from_csv_definitions` on
every `to_rdf_graph` call.

**CSV columns:**

| Column | Meaning |
|--------|---------|
| `class` | Model class to match, or `*` for all asset types |
| `method` | Method called on `self` to get the value(s) |
| `property` | RDF predicate — `eval`'d, so it can use `JERMVocab`, `RDF::Vocab::DC`, etc. |
| `uri or literal` | `u` = emit a URI/resource link; `l` = emit a string literal |
| `transformation` | Optional Ruby snippet `eval`'d on each individual `item` |
| `collection transformation` | Optional Ruby snippet `eval`'d on the whole collection |

**Example rows:**

```
*,title,RDF::Vocab::DC.title,l,,
```
→ for every asset: `<resource> dc:title "My Study" .`

```
*,creators,JERMVocab.hasCreator,u,item.class.name=='User' ? item.person : item,
```
→ resolves `User` to their `Person` before emitting the URI link.

```
Study,investigation,JERMVocab.isPartOf,u,,
```
→ only for `Study`: emits a URI link to the parent investigation.

**Processing flow in `generate_for_csv_row`:**

1. Skip the header row (`class` == `"class"`).
2. Match `class` column against `self.class.name` (or `*` for all).
3. Check `respond_to?(method)` — log a warning and skip if not found.
4. Call `subject.send(method)` to get values; wrap single values in an array.
5. Reject non-RDF-capable `ActiveRecord::Base` objects.
6. Apply `collection_transformation` if present (e.g. `compact`).
7. For each item, apply `transformation` if present, then emit either a URI triple or a literal triple.

The CSV covers all **fixed, schema-level** relationships (ISA hierarchy links,
contributors, timestamps, DOIs, etc.). The `extended_metadata_triples` step
(added in this branch) covers **user-defined, dynamic** attributes.
