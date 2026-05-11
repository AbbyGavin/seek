require 'json'

module Seek
  module WorkflowExtractors
    # Dummy class for testing. The argument should be a json string
    class DummyExtractor < Base
      attr_accessor :title, :description

      def initialize(to_extract)
        super
        @to_extract = to_extract
      end

      def extract
        j = JSON.parse(@to_extract)
        @title = j['title']
        @description = j['description']
      end

      def selt.file_extensions
        ['json']
      end
    end
  end
end
