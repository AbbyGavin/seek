require 'json'

module Seek
  module WorkflowExtractors
    # Dummy class for testing. The argument should be a json string
    class Dummy < Base
      def metadata
        return @metadata if @metadata

        metadata = super
        json_file = @io.read
        j = JSON.parse(json_file)
        metadata[:title] = j['title']
        metadata[:description] = j['description']

        metadata
      end

      def self.file_extensions
        ['json']
      end
    end
  end
end
