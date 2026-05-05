require 'test_helper'

# Cycle 10: Regression and backwards-compatibility tests.
# Guarantees that the DCAT and HealthDCAT-AP additions (Cycles 3–9) have not
# broken the pre-existing JERM / Dublin-Core RDF export, and that existing
# DCAT-AP 3.0 consumers receive the mandatory triples they need.
class RdfBackwardsCompatTest < ActiveSupport::TestCase
  JERM_NS = 'http://jermontology.org/ontology/JERMOntology#'.freeze
  DCAT_NS = 'http://www.w3.org/ns/dcat#'.freeze
  DC_NS   = 'http://purl.org/dc/terms/'.freeze

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def parse_turtle(ttl)
    RDF::Graph.new { |g| RDF::Reader.for(:ttl).new(ttl) { |r| g << r } }
  end

  def subject_uri(resource)
    RDF::URI(resource.rdf_resource.to_s)
  end

  def types_for(graph, subject)
    graph.query([subject, RDF.type, nil]).map { |s| s.object.to_s }
  end

  def objects_for(graph, subject, predicate_uri)
    graph.query([subject, RDF::URI(predicate_uri), nil]).map(&:object)
  end

  # ---------------------------------------------------------------------------
  # Group 1: JERM triples still present for plain resources (regression)
  # ---------------------------------------------------------------------------

  test 'DataFile without HealthDCAT still emits jermontology type triple' do
    df    = FactoryBot.create(:public_data_file)
    graph = parse_turtle(df.to_rdf)
    types = types_for(graph, subject_uri(df))
    assert types.any? { |t| t.include?('jermontology') },
           "Expected a jermontology type triple for DataFile, got: #{types.inspect}"
  end

  test 'DataFile without HealthDCAT still emits dc:title triple' do
    df    = FactoryBot.create(:public_data_file, title: 'Regression DataFile Title')
    graph = parse_turtle(df.to_rdf)
    titles = objects_for(graph, subject_uri(df), "#{DC_NS}title").map(&:to_s)
    assert titles.any? { |t| t.include?('Regression DataFile Title') },
           "Expected dc:title triple, got: #{titles.inspect}"
  end

  test 'DataFile without HealthDCAT still emits jerm:title triple' do
    df    = FactoryBot.create(:public_data_file, title: 'JERM Title Test')
    graph = parse_turtle(df.to_rdf)
    titles = objects_for(graph, subject_uri(df), "#{JERM_NS}title").map(&:to_s)
    assert titles.any? { |t| t.include?('JERM Title Test') },
           "Expected jerm:title triple, got: #{titles.inspect}"
  end

  test 'DataFile without HealthDCAT still emits jerm:seekID triple' do
    df    = FactoryBot.create(:public_data_file)
    graph = parse_turtle(df.to_rdf)
    seek_ids = objects_for(graph, subject_uri(df), "#{JERM_NS}seekID")
    assert seek_ids.any?, 'Expected jerm:seekID triple to be present'
  end

  test 'Assay without HealthDCAT still emits jermontology type triple' do
    assay = FactoryBot.create(:public_assay)
    graph = parse_turtle(assay.to_rdf)
    types = types_for(graph, subject_uri(assay))
    assert types.any? { |t| t.include?('jermontology') },
           "Expected jermontology type triple for Assay, got: #{types.inspect}"
  end

  test 'Investigation without HealthDCAT still emits jermontology type triple' do
    inv   = FactoryBot.create(:public_investigation)
    graph = parse_turtle(inv.to_rdf)
    types = types_for(graph, subject_uri(inv))
    assert types.any? { |t| t.include?('jermontology') },
           "Expected jermontology type triple for Investigation, got: #{types.inspect}"
  end

  test 'Sop without HealthDCAT still emits jermontology type triple' do
    sop   = FactoryBot.create(:public_sop)
    graph = parse_turtle(sop.to_rdf)
    types = types_for(graph, subject_uri(sop))
    assert types.any? { |t| t.include?('jermontology') },
           "Expected jermontology type triple for Sop, got: #{types.inspect}"
  end

  # ---------------------------------------------------------------------------
  # Group 2: DCAT coexists with JERM — both type triples present
  # ---------------------------------------------------------------------------

  test 'DataFile emits both jermontology type and dcat:Dataset simultaneously' do
    df    = FactoryBot.create(:public_data_file)
    graph = parse_turtle(df.to_rdf)
    types = types_for(graph, subject_uri(df))
    assert types.any? { |t| t.include?('jermontology') }, 'JERM type triple missing from DataFile'
    assert_includes types, "#{DCAT_NS}Dataset", 'dcat:Dataset missing from DataFile'
  end

  test 'Assay emits both jermontology type and dcat:Dataset simultaneously' do
    assay = FactoryBot.create(:public_assay)
    graph = parse_turtle(assay.to_rdf)
    types = types_for(graph, subject_uri(assay))
    assert types.any? { |t| t.include?('jermontology') }, 'JERM type triple missing from Assay'
    assert_includes types, "#{DCAT_NS}Dataset", 'dcat:Dataset missing from Assay'
  end

  test 'Sop does not gain a spurious dcat:Dataset type' do
    sop   = FactoryBot.create(:public_sop)
    graph = parse_turtle(sop.to_rdf)
    types = types_for(graph, subject_uri(sop))
    refute_includes types, "#{DCAT_NS}Dataset", 'Sop must not have dcat:Dataset (not in DCAT_CLASS_MAP)'
    refute_includes types, "#{DCAT_NS}Resource", 'Sop must not have dcat:Resource (not in DCAT_CLASS_MAP)'
  end

  test 'Investigation gets dcat:Resource not dcat:Dataset' do
    inv   = FactoryBot.create(:public_investigation)
    graph = parse_turtle(inv.to_rdf)
    types = types_for(graph, subject_uri(inv))
    assert_includes types, "#{DCAT_NS}Resource", 'Investigation should have dcat:Resource per DCAT_CLASS_MAP'
    refute_includes types, "#{DCAT_NS}Dataset",  'Investigation must not have dcat:Dataset'
  end

  # ---------------------------------------------------------------------------
  # Group 3: DCAT-AP 3.0 mandatory fields
  # ---------------------------------------------------------------------------

  test 'DataFile satisfies DCAT-AP 3.0 mandatory Dataset properties' do
    df    = FactoryBot.create(:public_data_file, title: 'DCAT-AP Test File', description: 'A regression test file.')
    graph = parse_turtle(df.to_rdf)
    sub   = subject_uri(df)

    assert_includes types_for(graph, sub), "#{DCAT_NS}Dataset",
                    'dcat:Dataset type required by DCAT-AP 3.0'

    titles = objects_for(graph, sub, "#{DC_NS}title").map(&:to_s)
    assert titles.any? { |t| t.include?('DCAT-AP Test File') },
           'dc:title required by DCAT-AP 3.0 missing or wrong value'

    descs = objects_for(graph, sub, "#{DC_NS}description").map(&:to_s)
    assert descs.any? { |d| d.include?('regression test file') },
           'dc:description required by DCAT-AP 3.0 missing or wrong value'

    dists = objects_for(graph, sub, "#{DCAT_NS}distribution")
    assert_equal 1, dists.size, 'dcat:distribution required by DCAT-AP 3.0'
  end

  test 'DataFile distribution blank node contains mandatory dcat:downloadURL' do
    df    = FactoryBot.create(:public_data_file)
    graph = parse_turtle(df.to_rdf)
    sub   = subject_uri(df)

    dist_node = objects_for(graph, sub, "#{DCAT_NS}distribution").first
    refute_nil dist_node, 'Expected a dcat:distribution blank node'

    dl_urls = objects_for(graph, dist_node, "#{DCAT_NS}downloadURL").map(&:to_s)
    assert dl_urls.any? { |u| u.include?('/download') },
           "Expected dcat:downloadURL in Distribution, got: #{dl_urls.inspect}"
  end

  test 'DataFile distribution blank node contains dcat:accessURL' do
    df    = FactoryBot.create(:public_data_file)
    graph = parse_turtle(df.to_rdf)
    sub   = subject_uri(df)

    dist_node = objects_for(graph, sub, "#{DCAT_NS}distribution").first
    access_urls = objects_for(graph, dist_node, "#{DCAT_NS}accessURL").map(&:to_s)
    assert access_urls.any?, 'Expected dcat:accessURL in Distribution'
  end

  test 'DataFile distribution blank node has dcat:Distribution type' do
    df    = FactoryBot.create(:public_data_file)
    graph = parse_turtle(df.to_rdf)
    sub   = subject_uri(df)

    dist_node  = objects_for(graph, sub, "#{DCAT_NS}distribution").first
    dist_types = types_for(graph, dist_node)
    assert_includes dist_types, "#{DCAT_NS}Distribution",
                    'Expected dcat:Distribution type on blank node'
  end

  test 'Assay satisfies DCAT-AP 3.0 Dataset type and dc:title' do
    assay = FactoryBot.create(:public_assay, title: 'Assay DCAT AP')
    graph = parse_turtle(assay.to_rdf)
    sub   = subject_uri(assay)
    assert_includes types_for(graph, sub), "#{DCAT_NS}Dataset"

    titles = objects_for(graph, sub, "#{DC_NS}title").map(&:to_s)
    assert titles.any? { |t| t.include?('Assay DCAT AP') },
           'dc:title missing from Assay RDF'
  end

  # ---------------------------------------------------------------------------
  # Group 4: HealthDCAT-AP extended metadata does not clobber JERM triples
  # ---------------------------------------------------------------------------

  test 'DataFile with HealthDCAT EMT still emits JERM type triple' do
    df    = build_minimal_healthdcat_data_file
    graph = parse_turtle(df.to_rdf)
    types = types_for(graph, subject_uri(df))
    assert types.any? { |t| t.include?('jermontology') },
           'JERM type triple missing when HealthDCAT EMT is attached'
  end

  test 'DataFile with HealthDCAT EMT still emits dcat:Dataset type' do
    df    = build_minimal_healthdcat_data_file
    graph = parse_turtle(df.to_rdf)
    assert_includes types_for(graph, subject_uri(df)), "#{DCAT_NS}Dataset",
                    'dcat:Dataset missing when HealthDCAT EMT is attached'
  end

  test 'DataFile with HealthDCAT EMT still emits dc:title' do
    df    = build_minimal_healthdcat_data_file(title: 'HealthDCAT DC Title Check')
    graph = parse_turtle(df.to_rdf)
    titles = objects_for(graph, subject_uri(df), "#{DC_NS}title").map(&:to_s)
    assert titles.any? { |t| t.include?('HealthDCAT DC Title Check') },
           'dc:title lost when HealthDCAT EMT is attached'
  end

  test 'DataFile with HealthDCAT EMT still emits jerm:seekID' do
    df    = build_minimal_healthdcat_data_file
    graph = parse_turtle(df.to_rdf)
    seek_ids = objects_for(graph, subject_uri(df), "#{JERM_NS}seekID")
    assert seek_ids.any?, 'jerm:seekID lost when HealthDCAT EMT is attached'
  end

  # ---------------------------------------------------------------------------
  # Group 5: All statements in graph are valid RDF
  # ---------------------------------------------------------------------------

  test 'DataFile RDF graph contains only valid statements' do
    df    = FactoryBot.create(:public_data_file, title: 'Valid RDF Test', description: 'Validity check.')
    graph = parse_turtle(df.to_rdf)
    graph.each_statement do |stmt|
      assert stmt.valid?, "Invalid RDF statement found: #{stmt.inspect}"
    end
    assert graph.statements.count.positive?, 'Expected at least one statement'
  end

  test 'Assay RDF graph contains only valid statements' do
    assay = FactoryBot.create(:public_assay)
    graph = parse_turtle(assay.to_rdf)
    graph.each_statement do |stmt|
      assert stmt.valid?, "Invalid RDF statement found: #{stmt.inspect}"
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  private

  def string_sat
    SampleAttributeType.find_or_initialize_by(title: 'String BC').tap do |sat|
      sat.base_type = Seek::Samples::BaseType::STRING
      sat.regexp    = '.*'
      sat.save!(validate: false)
    end
  end

  def build_minimal_healthdcat_data_file(title: 'HealthDCAT BC Test')
    emt = ExtendedMetadataType.find_or_initialize_by(
      title: 'Minimal HealthDCAT BC', supported_type: 'DataFile'
    )
    if emt.new_record?
      emt.extended_metadata_attributes << ExtendedMetadataAttribute.new(
        title: 'population_coverage',
        pid: 'http://healthdataportal.eu/ns/health#populationCoverage',
        sample_attribute_type: string_sat
      )
      emt.save!
    end

    em = ExtendedMetadata.new(extended_metadata_type: emt)
    em.set_attribute_value('population_coverage', 'All age groups')

    FactoryBot.create(:public_data_file, title: title,
                                         description: 'Backwards compatibility test.', extended_metadata: em)
  end
end
