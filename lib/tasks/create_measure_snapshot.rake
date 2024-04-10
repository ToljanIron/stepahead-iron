require './app/helpers/cds_util_helper.rb'
require './lib/tasks/modules/create_snapshot_helper.rb'
include CdsUtilHelper
include CreateSnapshotHelper

namespace :db do
  desc 'create_snapshot'
  task :create_snapshot, [:cid, :date, :type] => :environment do |_t, args|
    config = ActiveRecord::Base.configurations[Rails.env || 'development'] || ENV['DATABASE_URL']
    ActiveRecord::Base.establish_connection(config)
    cid   = args[:cid]  || ENV['COMPANY_ID'] || (fail 'No company ID given (cid)')
    date  = args[:date] || ENV['SDATE']      || Time.now.strftime('%Y-%m-%d')
    puts "Running with CID=#{cid}, date=#{date}"
    CdsUtilHelper.cache_delete_all
    ActiveRecord::Base.transaction do
      begin
        CreateSnapshotHelper::create_company_snapshot_by_weeks(cid.to_i, date, true)
      rescue => e
        error = e.message[0..1000]
        puts "got exception: #{error}"
        puts e.backtrace
        raise ActiveRecord::Rollback
      end
    end
  end
end
