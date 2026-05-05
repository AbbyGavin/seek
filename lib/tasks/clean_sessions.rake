namespace :db do
  namespace :sessions do
    desc "Delete old sessions in batches to avoid lock timeouts"
    task clean_batch: :environment do
      batch_size = ENV['BATCH_SIZE']&.to_i || 1_000
      days_old = ENV['DAYS_OLD']&.to_i || 7
      cutoff_date = days_old.days.ago

      deleted_total = 0
      loop do
        deleted_count = ActiveRecord::SessionStore::Session.where("updated_at < ?", cutoff_date).limit(batch_size).delete_all
        deleted_total += deleted_count

        puts "Deleted #{deleted_count} sessions (Total: #{deleted_total})"
        break if deleted_count < batch_size

        sleep(1) # Wait longer between batches to release locks
      end

      puts "\nFinished! Deleted #{deleted_total} total sessions older than #{days_old} days."
    end
  end
end

# Delete sessions older than 7 days (default)
# bundle exec rake db:sessions:clean_batch

# Delete sessions older than 30 days
# bundle exec rake db:sessions:clean_batch DAYS_OLD=30