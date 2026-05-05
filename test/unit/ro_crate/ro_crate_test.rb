require 'test_helper'

class RoCrateExploringTest < ActiveSupport::TestCase

  test 'ro_crate for investigation with studies and assays including extended metadata' do
    # Build an investigation with studies, assays, and extended metadata
    investigation = setup_test_case_investigation
    studies = investigation.studies

    ro_crate = ::ROCrate::Crate.new

    #
    # Add INVESTIGATION
    #
    investigation_entity = add_entity(ro_crate, investigation)
    ro_crate['mainEntity'] = investigation_entity.reference

    #
    # Add STUDIES
    #
    study_entities = studies.map do |study|
      add_entity(ro_crate, study)
    end

    # Link studies to investigation
    investigation_entity['hasPart'] = study_entities.map { |e| { '@id': e.id } }

    #
    # Add ASSAYS + DATAFILES
    #
    study_entities.zip(studies).each do |study_entity, study|
      assay_entities = []

      study.assays.each do |assay|
        assay_entity = add_entity(ro_crate, assay)

        # Add data files for this assay
        if assay.data_files.any?
          data_file_references = assay.data_files.map do |df|
            df_entity = ::ROCrate::DataEntity.new(
              ro_crate,
              df.content_blob.filepath,
              df.content_blob.original_filename,
              '@type': ['File', 'Dataset'],
              'name': df.title,
              'encodingFormat': df.content_blob.content_type
            )
            ro_crate.add_data_entity(df_entity)
            { '@id' => df_entity.id }
          end

          assay_entity['hasPart'] = data_file_references
        end

        assay_entities << assay_entity
      end

      study_entity['hasPart'] = assay_entities.map { |e| { '@id': e.id } }
    end

    write_crate(ro_crate, 'investigation_ro_crate.json')
  end

  def add_entity(crate, resource)
    entity = ::ROCrate::DataEntity.new(crate)

    entity.id = resource.rdf_seek_id
    entity.type = 'Dataset'
    entity['name'] = resource.title
    entity['description'] = resource.description

    extended_metadata = resource.extended_metadata

    if extended_metadata.present?
      attributes = extended_metadata.extended_metadata_type.extended_metadata_attributes.index_by(&:title)

      entity['additionalProperty'] = extended_metadata.data.map do |key, value|
        attribute = attributes[key.to_s]

        property_id = attribute&.pid.presence || key.to_s
        display_name = attribute&.label.presence || attribute&.title.presence || key.to_s.humanize

        {
          '@type' => 'PropertyValue',
          'name' => display_name,
          'propertyID' => property_id,
          'value' => value
        }
      end
    end

    crate.add_data_entity(entity)
    entity
  end

  private

  def write_crate(crate, filename = 'ro_crate.json')
    json = crate.metadata.generate
    pretty = JSON.pretty_generate(JSON.parse(json))
    path = Rails.root.join('tmp', filename)
    File.write(path, pretty)
    puts "\n RO-Crate saved to #{path}\n"
  end



  def setup_test_case_investigation
    FactoryBot.create(:fairdata_test_case_investigation_extended_metadata)
    FactoryBot.create(:fairdata_test_case_study_extended_metadata)
    FactoryBot.create(:fairdata_test_case_obsv_unit_extended_metadata)
    FactoryBot.create(:fairdata_test_case_assay_extended_metadata)
    FactoryBot.create(:fairdatastation_test_case_sample_type)
    FactoryBot.create(:experimental_assay_class)

    contributor = FactoryBot.create(:person)
    project = contributor.projects.first
    policy = FactoryBot.create(:public_policy)
    path = "#{Rails.root}/test/fixtures/files/fair_data_station/seek-fair-data-station-test-case.ttl"
    inv = Seek::FairDataStation::Reader.new.parse_graph(path).first
    investigation = Seek::FairDataStation::Writer.new.construct_isa(inv, contributor, [project], policy)
    assert_difference('Investigation.count', 1) do
      investigation.save!
    end
    assert_equal 'seek-test-investigation', investigation.external_identifier
    investigation
  end


end



