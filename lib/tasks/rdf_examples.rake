# frozen_string_literal: true

namespace :rdf do
  desc 'Generate example Turtle and JSON-LD output for the COVID-19 HealthDCAT-AP DataFile seed. ' \
       'Writes to docs/examples/. Requires the healthdcat_covid19_example seed to have been run.'
  task generate_examples: :environment do
    require 'fileutils'

    output_dir = Rails.root.join('docs/examples')
    FileUtils.mkdir_p(output_dir)

    df = DataFile.find_by(title: 'COVID-19 Patient Registry')
    unless df
      abort 'COVID-19 Patient Registry DataFile not found. ' \
            'Run: bundle exec rake db:seed:extended_metadata_drafts:healthdcat_covid19_example'
    end

    ttl_path    = output_dir.join('covid19_registry.ttl')
    jsonld_path = output_dir.join('covid19_registry.jsonld')

    File.write(ttl_path, df.to_rdf)
    puts "Written: #{ttl_path}"

    File.write(jsonld_path, df.to_json_ld)
    puts "Written: #{jsonld_path}"

    puts 'Example files generated successfully.'
  end
end
