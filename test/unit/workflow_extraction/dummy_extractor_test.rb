require 'test_helper'

class DummyExtractorTest < ActiveSupport::TestCase
  test 'extracts metadata' do
    wf = open_fixture_file('workflows/dummy_test.json')
    extractor = Seek::WorkflowExtractors::DummyExtractor.new(wf)
    extractor.extract

    assert_equal 'a title', extractor.title
    assert_equal 'some description', extractor.description
  end
end
