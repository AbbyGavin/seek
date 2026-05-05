# General functionalities
def create_sample_controlled_vocab_terms_attributes(array)
  attributes = []
  array.each do |type|
    attributes << { label: type }
  end
  attributes
end

disable_authorization_checks do




  unless ExtendedMetadataType.where(title: 'Bioimage_Archive_Study_Publication_metadata').any?
    study_publication = ExtendedMetadataType.new(title: 'Bioimage_Archive_Study_Publication_metadata', supported_type: 'ExtendedMetadata')
    study_publication.extended_metadata_attributes << ExtendedMetadataAttribute.new(title: 'bia_study_publication_title', required: true,
                                                                                    sample_attribute_type: SampleAttributeType.find_by(title: 'String'), label: 'Title',
                                                                                    description: 'The title of the publication.')
    study_publication.extended_metadata_attributes << ExtendedMetadataAttribute.new(title: 'bia_study_publication_authors', required: true,
                                                                                    sample_attribute_type: SampleAttributeType.find_by(title: 'String'), label: 'Authors',
                                                                                    description: 'The authors of the publication.')
    study_publication.save!
  end
  study_publication_emt = ExtendedMetadataType.where(title: 'Bioimage_Archive_Study_Publication_metadata').first




  unless ExtendedMetadataType.where(title: 'Bioimage_Archive_Study_metadata(shorter)', supported_type: 'ExtendedMetadata').any?
    bia_study = ExtendedMetadataType.new(title: 'Bioimage_Archive_Study_metadata(shorter)', supported_type: 'ExtendedMetadata')
    bia_study.extended_metadata_attributes << ExtendedMetadataAttribute.new(title: 'bia_study_publications', required: false, label: 'Publications',
                                                                            sample_attribute_type: SampleAttributeType.where(title: 'Linked Extended Metadata (multiple)').first,
                                                                            linked_extended_metadata_type: study_publication_emt)

    bia_study.save!
  end
end

bia_study_emt = ExtendedMetadataType.where(title: 'Bioimage_Archive_Study_metadata(shorter)').first

unless ExtendedMetadataType.where(title: 'Bioimage_Archive_REMBI_metadata').any?
  rembi_emt = ExtendedMetadataType.new(title: 'Bioimage_Archive_REMBI_metadata', supported_type: 'Study')

  rembi_emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(title: 'BioImage_Archive_Study', 
                                                                          required: true,
                                                                          sample_attribute_type: SampleAttributeType.where(title: 'Linked Extended Metadata').first,
                                                                          linked_extended_metadata_type: bia_study_emt)
  rembi_emt.save!
end
puts 'Seeded Bioimage Archive extended metadata'
