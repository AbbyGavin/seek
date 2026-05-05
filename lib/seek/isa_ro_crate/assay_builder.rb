# frozen_string_literal: true

require 'ro_crate'

module Seek
  module ISAroCrate
    # Builds a minimal RO-Crate for an Assay
    class AssayBuilder
      attr_reader :assay, :crate

      def initialize(assay)
        @assay = assay
        @crate = ::ROCrate::Crate.new
        @crate.metadata['@context'] = "https://w3id.org/ro/crate/1.2/context"
      end

      # Main entry point
      def build
        add_data_files
        add_assay_entity
        add_root_dataset
        crate
      end

      private

      # Add all DataFiles linked to this Assay
      def add_data_files
        assay.data_files.each do |data_file|
          add_data_file_entity(data_file)
        end
      end

      def add_data_file_entity(data_file)
        blob = data_file.content_blob
        filename = blob.original_filename

        # Use with_tempfile to handle both local and Shrine-backed files
        if blob.respond_to?(:with_tempfile)
          blob.with_tempfile do |tempfile|
            file_entity = ::ROCrate::DataEntity.new(
              crate,
              tempfile.path,
              filename,
              '@type' => ['File'],
              'name' => data_file.title,
              'description' => data_file.description,
              'encodingFormat' => blob.content_type
            )
            crate.add_data_entity(file_entity)
          end
        else
          # Fallback for non-ContentBlob file types
          file_entity = ::ROCrate::DataEntity.new(
            crate,
            blob.filepath,
            filename,
            '@type' => ['File'],
            'name' => data_file.title,
            'description' => data_file.description,
            'encodingFormat' => blob.content_type
          )
          crate.add_data_entity(file_entity)
        end
      end

      def add_assay_entity
        assay_entity = ::ROCrate::ContextualEntity.new(crate, "assay_#{assay.id}")
        assay_entity['@type'] = ['Dataset', 'Assay']
        assay_entity['name'] = assay.title
        assay_entity['description'] = assay.description
        assay_entity['additionalType'] = 'https://jermontology.org/ontology/JERMOntology#Assay'

        # Link data files
        assay_entity['hasPart'] = assay.data_files.map { |df| { '@id' => df.content_blob.original_filename } }

        crate.add_contextual_entity(assay_entity)
      end

      def add_root_dataset
        root = ::ROCrate::ContextualEntity.new(crate, './')
        root['@type'] = ['Dataset']
        root['name'] = "RO-Crate for #{assay.title}"
        root['hasPart'] = [{ '@id' => "assay_#{assay.id}" }]
        crate.add_contextual_entity(root)
      end
    end
  end
end
