class SendPersonalReportJob < ApplicationJob
  queue_as :send_personal_report

  def perform(pid)
    #make sure the report folder exists
    directory_name='public/personal_report_images'
    Dir.mkdir(directory_name) unless File.exist?(directory_name)
    generated_pdf_tmp_dir = 'tmp/data/personal_report'
    Dir.mkdir(generated_pdf_tmp_dir) unless File.exist?(generated_pdf_tmp_dir)

    qp = QuestionnaireParticipant.find(pid)
    qq = QuestionnaireQuestion.find_by(id: qp.current_questiannair_question_id)
    @base_url = Rails.env == 'test' || Rails.env == 'development' ? 'http://localhost:3000/' : ENV['STEPAHEAD_BASE_URL']
    @aq = Questionnaire.find(qp.questionnaire_id)
    @employee = Employee.find(qp.employee_id)
    @emps = hash_employees_of_company_by_token(qp.token, true)
    @report_stats = qp.personal_report_stats
    qp.personal_report_map_image
    qp.personal_report_org_map_image

    pdf_options = {
      page_size: 'A4',
      orientation: 'Portrait',
      margin_top: '0.5in',
      margin_right: '0.25in',
      margin_bottom: '0.5in',
      margin_left: '0.25in'
    }

    lookup_context = ActionView::LookupContext.new(ActionController::Base.view_paths)
    view = ActionView::Base.with_empty_template_cache.new(lookup_context, {}, nil)
    view.class.include Rails.application.routes.url_helpers
    view.class.include ApplicationHelper

    html_content = view.render(template: 'personal_report/generate_pdf.html.erb', layout: 'layouts/personal_report.html.erb', locals: { base_url: @base_url, employee: @employee, aq: @aq, emps: @emps, report_stats: @report_stats, qp: qp })
    pdf_kit = PDFKit.new(html_content, pdf_options)
    pdf_data = pdf_kit.to_pdf
    file_path = Rails.root.join('tmp', "data/personal_report/#{qp.token}.pdf")
    
    File.open(file_path, 'wb') do |file|
      file << pdf_data
    end

    PersonalReportMailer.personal_report_email(@employee.email, file_path.to_s, @aq.personal_report_email_subject || 'Personal Report', @aq.personal_report_email_body || 'Personal Report').deliver_now
  end
end
