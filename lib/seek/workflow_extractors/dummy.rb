require 'json'

module Seek
  module WorkflowExtractors
    # Dummy class for testing. The argument should be a json string
    class Dummy < Base
      def metadata
        return @metadata if @metadata

        metadata = super
        puts @io
        @json_file = if @io.is_a?(Pathname)
                       File.read(@io.to_s)
                     elsif @io.respond_to?('path')
                       File.read(@io.path)
                     else
                       @io.read
                     end

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
