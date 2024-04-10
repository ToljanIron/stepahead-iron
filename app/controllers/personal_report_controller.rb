class PersonalReportController < ApiController
  include QuestionnaireHelper
  
  def generate_pdf
  
    #make sure the report folder exists
    directory_name='public/personal_report_images'
    Dir.mkdir(directory_name) unless File.exist?(directory_name)

    token = params["token"]
    qd = get_questionnaire_details(token)
    @qp = QuestionnaireParticipant.find(qd[:qpid])
    qq = QuestionnaireQuestion.find_by(id: @qp.current_questiannair_question_id)
    @base_url = Rails.env == 'test' || Rails.env == 'development' ? 'http://localhost:3000/' : ENV['STEPAHEAD_BASE_URL']
    @aq = Questionnaire.find(@qp.questionnaire_id)
    @employee = Employee.find(@qp.employee_id)
    @emps = hash_employees_of_company_by_token(token, true)
    @report_stats = @qp.personal_report_stats
    @qp.personal_report_map_image
    @qp.personal_report_org_map_image    

    respond_to do |format|
      format.html
      format.pdf do
        pdf_options = {
          page_size: 'A4',
          orientation: 'Portrait',
          margin_top: '0in',
          margin_right: '0.25in',
          margin_bottom: '0in',
          margin_left: '0.25in'
        }
        html = render_to_string(template: 'personal_report/generate_pdf.html.erb', layout: 'personal_report.html.erb', locals: { base_url: @base_url, employee: @employee, aq: @aq, emps: @emps, report_stats: @report_stats, qp: @qp })
        pdf = PDFKit.new(html, pdf_options)
        send_data pdf.to_pdf, filename: "report_#{token}.pdf", type: 'application/pdf'
      end
    end
  end

  def send_personal_report
    pids = params["pids"]

    pids.each do |pid|
      SendPersonalReportJob.perform_later(pid)      
    end

    render json: { success: true }
  end
end
