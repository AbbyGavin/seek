# frozen_string_literal: true

require_relative 'assay_builder'

module Seek
  module ISAroCrate

     class Exporter
      attr_reader :assay, :crate_path

      def initialize(assay, crate_path: nil)
        @assay = assay
        @crate_path = crate_path || default_path
      end

      def export
        builder = AssayBuilder.new(assay)
        crate = builder.build
        crate.save(crate_path)
        crate_path
      end

      private

      def default_path
        Rails.root.join('tmp', "isa_ro_crate_assay_#{assay.id}")
      end
    end
  end
end
