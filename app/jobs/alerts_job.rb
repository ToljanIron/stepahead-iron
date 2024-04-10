class AlertsJob  < ApplicationJob
queue_as :alerts

  def perform
    puts 'create_alerts job started'
    EventLog.log_event(message: 'create_alerts job started', event_type_name: 'ALERTS_JOB' )
    cids = Company.pluck(:id)

    cids.each do |cid|
      sid = Snapshot.where(company_id: cid)
                    .order(timestamp: :desc)
                    .last.id
      [200,201,203,204,205,206,207,208,303].each do |aid|
        puts "Working on company: #{cid}, algorithm: #{aid}"
        CreateAlertsTaskHelper.create_alerts(cid, sid, aid)
      end
    end

    EventLog.log_event(message: 'create_alerts job completed', event_type_name: 'ALERTS_JOB')
  end

  def error(job, ex)
    msg = "alerts job error: #{ex.message}"
    puts msg
    EventLog.log_event(message: msg, event_type_name: 'ALERTS_JOB')
    puts ex.backtrace
  end

  def failure(job)
    msg = 'AlertsJob failure'
    puts msg
    EventLog.log_event(message: msg, event_type_name: 'ALERTS_JOB')
  end
end
