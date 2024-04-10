namespace :db do
	require 'sidekiq/api'
	desc 'send personal report job'
	
	task send_personal_report: :environment do
		queue = Sidekiq::Queue.new("send_personal_report")
		queue.each do |job|
			Rails.logger.info "Started at #{Time.now}"
			job.klass.constantize.new.perform(*job.args)
			job.delete
			Rails.logger.info "Finished at #{Time.now}"
		end
	end
end