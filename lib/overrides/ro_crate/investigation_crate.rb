require 'ro_crate'

module ROCrate
  class InvestigationCrate < ::ROCrate::Crate
    PROFILE_REF = { '@id' => 'https://w3id.org/ro/crate/1.1' }.freeze

    include ActiveModel::Model

    validates :main_investigation, presence: true

    # Similar to WorkflowCrate:
    properties(%w[mainEntity mentions about hasPart])

    def initialize(*args)
      super

      conforms = metadata['conformsTo']
      if conforms.is_a?(Array)
        metadata['conformsTo'] << PROFILE_REF
      else
        metadata['conformsTo'] = [{ '@id' => ::ROCrate::Metadata::SPEC }, PROFILE_REF]
      end
    end

    #
    # MAIN ENTITY (Investigation)
    #
    def main_investigation
      main_entity
    end

    def main_investigation=(entity)
      add_data_entity(entity).tap { |entity| self.main_entity = entity }
    end

    #
    # Convenience accessors to SEEK structure
    #
    def studies
      Array(main_investigation&.has_part).select { |e| e.has_type?('Study') }
    end

    def assays
      studies.flat_map { |s| Array(s.has_part) }.select { |e| e.has_type?('Assay') }
    end

    #
    # Example accessor for files attached to investigation-level
    #
    def data_files
      (Array(mentions) | Array(about)).select { |e| e.has_type?('File') }
    end

    #
    # Retrieve crate entry by path
    #
    def find_entry(path)
      entries[path]
    end

    #
    # A canonical "source" identifier
    #
    def source_url
      url = id if id.start_with?('http')
      url || self['isBasedOn'] || self['url'] || (self.main_investigation && self.main_investigation['url'])
    end
  end
end
