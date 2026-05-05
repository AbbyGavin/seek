You are acting as a senior Rails architect and implementation planner.

I need a **step-by-step implementation plan** for adding **configurable file storage backends** to FAIRDOM-SEEK.

## Context

FAIRDOM-SEEK currently stores uploaded files through `ContentBlob`, using the existing filestore/local filesystem approach.

I want to introduce a **supported configuration switch per SEEK instance** so an administrator can choose between:

1. **Local filesystem storage**

    * for current behavior, simple deployments, and backward compatibility

2. **S3-compatible object storage**

    * e.g. MinIO, AWS S3, or institutional S3 providers

## Goal

Design a clean, maintainable approach so the **same SEEK codebase** can run with either:

* local file storage, or
* S3-compatible object storage

depending only on instance configuration.

## What I need from you

Please **inspect the codebase structure and relevant upload/storage paths** and then produce a **practical implementation plan**.

I do **not** want a big-bang plan.
I want the work broken down into **small, independent development cycles**.

## Required output format

For each cycle, provide:

* **Cycle title**
* **Objective**
* **Why this step comes now**
* **Exact code areas likely to change**

    * models
    * services
    * upload logic
    * configuration
    * initializers
    * background jobs
    * tests
* **Implementation steps**

    * small, concrete coding tasks
* **Risks / things to verify**
* **Definition of done**
* **Tests to add/update**

    * unit tests
    * integration tests
    * regression tests
* **Suggested commit scope**

    * what should be included in one PR / commit only

## Important constraints

Please optimize for:

* **small independent increments**
* **backward compatibility**
* **safe migration path**
* **minimal disruption to existing instances**
* **clear separation of storage concerns**
* **testability**
* **ability to ship partial progress safely**

## Specific things I want you to check in the codebase

Please explicitly identify and account for:

* where `ContentBlob` currently manages file paths and file persistence
* where uploaded files are written to disk
* where files are read back / streamed / downloaded
* whether storage logic is mixed into models, uploaders, or services
* whether existing abstractions already exist that could support a storage adapter pattern
* where configuration is currently defined for filestores
* how background processing or delayed jobs interact with uploads
* how existing tests cover file upload/download behavior

## Architectural guidance

Please propose an approach that keeps storage backend selection configurable, ideally through a clean abstraction such as a storage service / adapter layer, rather than scattering conditionals throughout the code.

Please also cover:

* whether local storage should remain the default
* how instance configuration should look
* how S3 credentials/endpoints/buckets should be configured
* how to support S3-compatible providers, not just AWS
* how URL generation or download streaming might differ between local and S3
* how to avoid breaking existing stored files
* whether migration of existing files should be in scope now or deferred
* what should be implemented first vs postponed

## Very important planning rules

* Do **not** jump directly to final architecture without showing the incremental path.
* Prefer **many small cycles** over a few large ones.
* Each cycle must be independently reviewable and mergeable.
* Each cycle must include tests.
* Call out any cycle that should be feature-flagged.
* Separate “foundation/refactoring” cycles from “behavior change” cycles.
* Distinguish clearly between:

    * preparation work
    * introducing abstraction
    * local backend implementation
    * S3 backend implementation
    * configuration wiring
    * test hardening
    * migration/follow-up work

## Deliverables

Please provide:

1. a short summary of the recommended architecture
2. a detailed sequence of small development cycles
3. for each cycle, the concrete tests to add
4. a final section called **“Suggested implementation order”**
5. a final section called **“What I would explicitly defer”**

If you see multiple viable implementation strategies, briefly compare them and recommend one.
