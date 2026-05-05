# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About This Project

FAIRDOM-SEEK is a Research Data Management platform implementing the ISA (Investigation-Study-Assay) framework. It manages scientific datasets, models, simulations, SOPs, workflows, publications, and related research outputs across projects and institutions. It supports DOI minting, RDF/semantic queries, full-text search via Solr, OAuth2, and integrations with Galaxy, openBIS, Zenodo, DataCite, and Bio.tools.

## Commands

### Tests

```bash
# Run all unit tests
bundle exec rails test test/unit

# Run all functional (controller) tests
bundle exec rails test test/functional

# Run all integration tests
bundle exec rails test test/integration

# Run a specific test file
bundle exec rails test test/unit/models/person_test.rb

# Run a specific test by line number
bundle exec rails test test/unit/models/person_test.rb:42

# Run RSpec tests
bundle exec rspec spec/
bundle exec rspec spec/models/person_spec.rb:42
```

### Database

```bash
bundle exec rake db:migrate
bundle exec rake db:seed
bundle exec rake seek:upgrade   # SEEK-specific upgrade task (runs migrations + seeds)
```

### Linting

```bash
bundle exec rubocop
```

### Assets

```bash
bundle exec rake assets:precompile
```

## Architecture

### ISA Domain Hierarchy

The core domain follows the ISA model:
- `Investigation` → `Study` → `Assay` (linked to asset types)
- Assets: `DataFile`, `Model`, `Sop`, `Workflow`, `Publication`, `Presentation`, `Document`, `Sample`
- Containers: `Project`, `Institution`, `WorkGroup` (links institutions to projects)
- People belong to projects via work groups with role-based permissions

### Controllers & Standard Actions

Most asset controllers inherit shared CRUD behaviour from `lib/seek/assets_standard_controller_actions.rb`. API endpoints (JSON-API) live under `app/controllers/api/` with serializers in `app/serializers/`. The API supports GA4GH TRS for workflows.

### Models & Concerns

`app/models/concerns/` contains the heavy lifting:
- `HasExtendedMetadata` – flexible custom attributes via `ExtendedMetadata` / `ExtendedMetadataType`
- `HasControlledVocabularyAnnotations` – semantic tagging
- `HasExternalIdentifier` – links to openBIS and other external systems
- `Versioned` / `ActsAsVersionedResource` – versioning for DataFiles, Models, SOPs, Workflows
- `Subscribable`, `Favouritable`, `Taggable` – cross-cutting asset behaviours

### Authorization

Policy-based access control: each resource has a `Policy` record. `Authorization` module in `lib/seek/` enforces read/write/manage/download checks. Gatekeepers can approve/reject access requests. Role types: owner, manager, editor, viewer (defined in `app/models/role.rb`).

### Service Layer (`lib/seek/`)

Key subdirectories:
- `api/` – JSON-API rendering, filtering, sorting helpers
- `doi/` – DataCite/Crossref DOI minting
- `ontologies/` – Assay/technology type management (OWL ontology)
- `renderers/` – Content preview system (PDF, Markdown, notebook, YouTube, iframe, etc.)
- `publishing/` – Gatekeeper workflow, Zenodo publishing
- `rdf/` – RDF generation, Virtuoso SPARQL integration
- `search/` – Sunspot/Solr full-text search configuration
- `isa_ro_crate/` – RO-Crate export/import for ISA
- `workflow_extractors/` – Workflow diagram extraction (CWL, Nextflow, Galaxy, Snakemake)

### Background Jobs

`app/jobs/` uses Delayed Job. Key jobs: subscription email delivery, openBIS sync, auth lookup rebuilding, asset reindexing, Life Monitor status checks, FAIR Data Station sync.

### Content Storage

`ContentBlob` is the central file storage abstraction. Assets can point to remote URLs or uploaded files. `ContentBlob#file_exists?` / `#retrieve_remote` handle both.

### Testing Conventions

- Tests use Minitest with `test/fixtures/` for test data and `test/factories/` (Factory Bot) for programmatic creation.
- `i_suck_and_my_tests_are_order_dependent!` is set — do not assume test isolation.
- VCR cassettes in `test/vcr_cassettes/` record HTTP interactions; CI runs with `:none` (no new cassettes).
- WebMock stubs external HTTP; add stubs or cassettes when hitting new external services in tests.
- Most functional/integration tests require an authenticated user — use `login_as(users(:quentin))` or equivalent fixture user.

### Database

Supports MySQL 8.4, PostgreSQL 14, SQLite3. MySQL is the primary CI target. Use `utf8mb4_unicode_ci` collation when creating MySQL databases for tests.

## Key Conventions

- Extended metadata types (`ExtendedMetadataType`) drive dynamic custom fields on most asset types — see `db/seeds/extended_metadata_drafts/` for examples.
- Routes follow Rails REST conventions; nested resources reflect ISA relationships.
- `config/default_data/` contains seed data loaded at boot for controlled vocabularies and settings.
- `config/initializers/` has 29 initializers — check here for feature flags, third-party config, and monkey patches.
