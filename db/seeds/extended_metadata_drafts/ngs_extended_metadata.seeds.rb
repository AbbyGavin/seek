# Define a method to create Extended Metadata Attributes
def create_extended_metadata_attribute(title:, required:, label:, description:, sample_attribute_type:)
    ExtendedMetadataAttribute.where(title: title).first_or_create!(
      title: title,
      required: required,
      label: label,
      description: description,
      sample_attribute_type: sample_attribute_type
    )
end

# NGS Extended Metadata
ngs_emt = ExtendedMetadataType.where(title: 'NGS', supported_type: 'Assay').first_or_create!(
  title: 'NGS',
  supported_type: 'Assay',
  extended_metadata_attributes: [
    create_extended_metadata_attribute(
      title: 'overall_design',
      required: true,
      label: 'Overall Design',
      description: 'Describe the overall experimental design.',
      sample_attribute_type: SampleAttributeType.where(title: 'Text').first
    ),
    create_extended_metadata_attribute(
      title: 'growth_protocol',
      required: false,
      label: 'Growth Protocol',
      description: 'Describe the conditions used to grow or maintain organisms or cells prior to the extract preparations.',
      sample_attribute_type: SampleAttributeType.where(title: 'Text').first
    ),
    create_extended_metadata_attribute(
      title: 'treatment_protocol',
      required: false,
      label: 'Treatment Protocol',
      description: 'If applicable, describes any treatments applied to the biological material prior to extract preparations.',
      sample_attribute_type: SampleAttributeType.where(title: 'Text').first
    ),
    create_extended_metadata_attribute(
      title: 'extract_protocol',
      required: true,
      label: 'Extract Protocol',
      description: 'Describes the protocols used to extract and prepare the material to be sequenced.',
      sample_attribute_type: SampleAttributeType.where(title: 'Text').first
    ),
    create_extended_metadata_attribute(
      title: 'library_construction_protocol',
      required: true,
      label: 'Library Construction Protocol',
      description: 'Describe the protocol used for library construction.',
      sample_attribute_type: SampleAttributeType.where(title: 'Text').first
    ),
    create_extended_metadata_attribute(
      title: 'library_strategy',
      required: true,
      label: 'Library Strategy',
      description: 'Specify the library strategy (e.g., miRNA-Seq, RNA-Seq, ChIP-Seq, ncRNA-Seq).',
      sample_attribute_type: SampleAttributeType.where(title: 'Text').first
    ),
    create_extended_metadata_attribute(
      title: 'data_processing_step',
      required: true,
      label: 'Data Processing Step',
      description: 'Provide details of how processed data files were generated.',
      sample_attribute_type: SampleAttributeType.where(title: 'Text').first
    )
  ]
)

puts "NGS Extended Metadata created successfully!"
