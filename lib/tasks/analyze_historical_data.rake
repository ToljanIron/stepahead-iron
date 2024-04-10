namespace :db do
  require './lib/tasks/modules/create_analyze_historical_data_helper.rb'
  include AnalyzeHistoricalDataHelper
  desc 'analyze_historical_data'
  task :analyze_historical_data, [:cid, :clean] => :environment do |_t, args|
    config = ActiveRecord::Base.configurations[Rails.env || 'development'] || ENV['DATABASE_URL']
    ActiveRecord::Base.establish_connection(config)

    CdsUtilHelper.cache_delete_all
    cid   = args[:cid] || -1
    clean = args[:clean] == 'true'

    msg = "Starting historical data processing for company: #{cid}"
    puts msg
    EventLog.log_event(message: msg)

    if clean
      puts "Clearing"
      NetworkSnapshotData.delete_all
      CdsMetricScore.delete_all
      RawDataEntry.all.update(processed: false)
      RawMeetingsData.all.update(processed: false)
      MeetingAttendee.delete_all
    end
    AnalyzeHistoricalDataHelper.run(cid)

    msg = "Done with historical data processing job"
    puts msg
    EventLog.log_event(message: msg)
  end
end
