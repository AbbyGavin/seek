require 'test_helper'

class DummyExtractorTest < ActiveSupport::TestCase
  test 'extracts metadata' do
    json_string = '{ "title": "a title", "description": "some description", "other": "another property" }'
    extractor = Seek::WorkflowExtractors::DummyExtractor.new(json_string)
    extractor.extract

    assert_equal 'a title', extractor.title
    assert_equal 'some description', extractor.description
  end
end
