# frozen_string_literal: true

require 'rubygems'
require 'rake'
require 'active_record/fixtures'

namespace :seek_stats_hits do

  task(who_action_what: :environment) do
    actions = %w[download create]
    types = %w[Model Sop DataFile Document Publication Presentation Workflow]


    activity_folder = Rails.root.join('tmp', 'activity')
    FileUtils.rm_rf(activity_folder) if File.directory?(activity_folder)
    FileUtils.mkdir_p(activity_folder)

    actions.each do |action|
      types.each do |type|
        conditions = { action: action, activity_loggable_type: type }
        conditions = conditions.delete_if { |_k, v| v.nil? }
        logs = ActivityLog.where(conditions).order(:created_at)
        if logs.size > 0
          filename = "#{Rails.root}/tmp/activity/#{action}-#{type || 'all'}.csv"
          File.open(filename, 'w') do |file|

            file << 'Created Date,Resource Type,Resource ID,Action,Project ID,Project_name,Person ID,Person Name'
            file << "\n"
            logs.each do |log|
              file << %("#{log.created_at.day} #{Date::MONTHNAMES[log.created_at.month]} #{log.created_at.year}")
              file << ','
              file << log.activity_loggable_type
              file << ','
              file << log.activity_loggable_id
              file << ','
              file << action
              file << ','
              project = !log.activity_loggable.nil? && log.activity_loggable.respond_to?(:projects) ? log.activity_loggable.projects.first : nil
              if project
                file << project.id
                file << ','
                file << %("#{project.title}")

              else
                file << %("","")
              end
              file << ','
              culprit = log.culprit
              if culprit && culprit.person
                file << culprit.person.id
                file << ','
                file << culprit.person.name
              else
                'false'
              end

              file << "\n"
            end
          end
          puts "csv written to #{filename}"
        end
      end
    end
  end
end
