namespace :db do
  require './lib/tasks/modules/precalculate_network_metrics_helper.rb'
  require './lib/tasks/modules/precalculate_metric_scores_for_custom_data_system_helper.rb'
  require './app/helpers/questionnaire_helper.rb'

  include PrecalculateNetworkMetricsHelper
  include PrecalculateMetricScoresForCustomDataSystemHelper
  include ActionView::Helpers::SanitizeHelper
  include QuestionnaireHelper

  desc 'precalculate network metrics'
  task :calculate_network_metrics, [:cid,:sid] => :environment do |t, args|
    cid = args[:cid] || -1
    sid = args[:sid] || -1
    Rails.logger.info "Started at #{Time.now}"
    PrecalculateNetworkMetricsHelper::calculate_questionnaire_score(cid.to_i,sid.to_i)
    Rails.logger.info "Finished at #{Time.now}"
  end
  desc 'precalculate open questionnaires metrics'
  task :calculate_open_questionnaires_metrics => :environment do |t, args|
    
    Questionnaire.where("created_at > :date ", date: "2023-12-31").where.not(state:['completed','processing']).each do | q |
    begin 
      cid=q.company_id
      sid=q.snapshot_id
      if(q.group.count>0)
        #delete all network snapshot data
        NetworkSnapshotData.where(snapshot_id:sid, company_id:cid).destroy_all
        QuestionnaireHelper.freeze_questionnaire_replies_in_snapshot(q.id)
        
        PrecalculateMetricScoresForCustomDataSystemHelper::cds_calculate_scores_for_generic_networks(cid, sid)
        PrecalculateNetworkMetricsHelper::calculate_questionnaire_score(cid,sid)
      end
    rescue =>e 
        puts("****************** could not calulate questionnaire " + sid.to_s+' company '+cid.to_s)
    end
    end
  end
end