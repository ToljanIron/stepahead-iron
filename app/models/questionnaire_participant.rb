# frozen_string_literal: true
class QuestionnaireParticipant < ActiveRecord::Base
  belongs_to :employee
  belongs_to :questionnaire
  has_many :question_replies
  has_one :sms_message

  BIG_NUMBER = 1000

  enum status: [:notstarted, :entered, :in_process, :completed,:unverified]
  enum participant_type: [:participant, :tester]

  def create_link
    create_token
    if Rails.env == 'test' || Rails.env == 'development'
      base_url = 'http://localhost:3000/'
    else
      Dotenv.load
      base_url = ENV['STEPAHEAD_BASE_URL']
    end

    return base_url + "/questionnaire?token=#{token}"
  end

  def create_token
    update(token: SecureRandom.hex[0..20]) unless token
  end

  def get_link
    if Rails.env == 'test' || Rails.env == 'development'
      base_url = 'http://localhost:3000/'
    else
      Dotenv.load
      base_url = ENV['STEPAHEAD_BASE_URL']
    end

    return base_url + "/questionnaire?token=#{token}"
  end

  #########################################################
  # Used for auto saving while answering a long question
  #########################################################
  def autosave(replies)
    curr_questionnaire_question = find_questionnaire_question(replies)

    replies.each do |r|
      reply_type = r[:reply_type]
      qr = QuestionReply.where(
                  questionnaire_id: questionnaire_id,
                  questionnaire_question_id: curr_questionnaire_question.id,
                  questionnaire_participant_id: id,
                  reffered_questionnaire_participant_id: r[:employee_id]).last
      if reply_type == 'do'
        if qr.nil?
          QuestionReply.create!(
                   questionnaire_id: questionnaire_id,
                   questionnaire_question_id: curr_questionnaire_question.id,
                   questionnaire_participant_id: id,
                   reffered_questionnaire_participant_id: r[:employee_id],
                   answer: r[:answer])
        else
          qr.update(answer: r[:answer])
        end
      elsif reply_type == 'undo'
        qr.try(:delete)
      else
        raise "Unknown reply_type: #{reply_type}"
      end
    end
  end

  def update_replies(replies)
    curr_questionnaire_question = find_questionnaire_question(replies)
    replies.select { |r| !r[:answer].nil? }.each do |r|
      qr = QuestionReply.where(questionnaire_id: questionnaire_id,
                               questionnaire_question_id: curr_questionnaire_question.id,
                               questionnaire_participant_id: id,
                               reffered_questionnaire_participant_id: r[:e_id])

      if qr.empty?
        if r[:e_id].blank?
          qp = QuestionnaireParticipant.find_by(employee_id: r[:employee_details_id], questionnaire_id: questionnaire_id)
          r[:e_id] = qp.id
        end
        QuestionReply.create!(questionnaire_id: questionnaire_id,
                              questionnaire_question_id: curr_questionnaire_question.id,
                              questionnaire_participant_id: id,
                              reffered_questionnaire_participant_id: r[:e_id],
                              answer: r[:answer])
      else
        qr.update_all(answer: r[:answer])
      end
    end
  end

  def find_next_question
    return QuestionnaireQuestion.find(current_questiannair_question_id), 'in process' if in_continue_later_status && current_questiannair_question_id
    res = nil
    answer_count = nil
    q_replies = nil
    q_index = 0
    status = 'in process'
    arr = questionnaire.questionnaire_questions.where(active: true).order(:order)
    arr.each do |qq|
      res = qq
      q_index += 1
      q_replies = question_replies
      answer_count = q_replies.where(answer: [true, false]).count
      break unless question_completed?(qq)
      status = 'done' if q_index == arr.count
    end
    status = 'first time' if answer_count.zero? && q_index == 1
    return res, status
  end

  def question_completed?(qq)
    return dependent_quesiton_completed?(qq) unless qq.depends_on_question.nil?
    return independent_quesiton_completed?(qq)
  end

  def independent_quesiton_completed?(qq)
    min     = qq.min.nil? ? BIG_NUMBER : qq.min
    answers = qq.question_replies.where(questionnaire_participant_id: id).count
    return answers >= min
  end

  def dependent_quesiton_completed?(qq)
    min = filter_only_relevant_qp(qq).count
    answers = qq.question_replies.where(questionnaire_participant_id: id).count
    return answers >= 1
  end

  def all_replies_for_questionnaire_question(q_id)
    res = []

    questionnaire_question = QuestionnaireQuestion.find(q_id)
    order_of_dependent_question = QuestionnaireQuestion.find(q_id).depends_on_question
    if order_of_dependent_question.nil?
      emps = if populate_automatically(questionnaire_question)
               QuestionnaireParticipant.find(filter_only_relevant_qp(questionnaire_question))
             else
               questionnaire_question.questionnaire_participants_by_name
             end
      emps.each do |qp|
        next if qp['id'] == id
        obj = {}
        obj[:employee_details_id] = qp['employee_id'].to_i
        obj[:e_id] = qp['id']
        obj[:answer] = nil
        res.push obj
      end
    else
      qps = QuestionnaireParticipant.find(filter_only_relevant_qp(questionnaire_question))
      qps.each do |qp|
        obj = {}
        obj[:employee_details_id] = qp.employee.id
        obj[:e_id] = qp.id
        obj[:answer] = nil
        res.push obj
      end
    end

    ## If returning after some replies have already been autosaved then
    ## need to remove them from the list.
    autosaved_qpids = QuestionReply
                        .where(questionnaire_question_id: q_id)
                        .where(questionnaire_participant_id: id)
                        .pluck(:reffered_questionnaire_participant_id)
    res = res.select do |r|
      !autosaved_qpids.include?(r[:e_id].to_i)
    end

    return res
  end

  def filter_only_relevant_qp(qq)
    if populate_automatically(qq)
      emps_arr = EmployeesConnection.where(employee_id: employee.id).pluck(:connection_id)
      selected_qps_ids = QuestionnaireParticipant.where(employee_id: emps_arr, questionnaire_id: questionnaire_id).pluck(:id)
    else
      selected_qps_ids = QuestionnaireQuestion
                           .find_by(id: qq.depends_on_question, questionnaire_id: qq.questionnaire_id)
                           .question_replies.where(questionnaire_participant_id: id, answer: true)
                           .pluck(:reffered_questionnaire_participant_id)
    end
    return selected_qps_ids
  end

  ## In order to decide whether to populate from EmployeesConnection or from
  ##   the first question need to find out whether the system was configured to
  ##   load questionnaire participants from the employees_connections table. Then
  ##   need to understand whether there was an independent question already or not,
  ##   because if there was then it has populated resultas.
  def populate_automatically(qq)
    return false if participant_type == 'tester'

    independent_question_was_populated = false
    qid = qq.questionnaire_id

    depends_on_question = qq.depends_on_question
    if !depends_on_question.nil?
      ind_question_id =  QuestionnaireQuestion.find_by(questionnaire_id: qid, order: qq.depends_on_question).try(:id)
      independent_question_was_populated = true if !ind_question_id.nil?
    end

    populate_from_employees_connections = CompanyConfigurationTable.find_by(key: 'populate_questionnaire_automatically', comp_id: employee[:company_id])
    populate_from_employees_connections = populate_from_employees_connections && populate_from_employees_connections[:value] == 'true'

    return populate_from_employees_connections && !independent_question_was_populated
  end

  def self.update_questionnaire_participant_status(status, current_question_position, total_questions = -1)
    return :entered if (status == 'first time' || current_question_position == 1) && total_questions != 1
    return :in_process if status == 'in process'
    return :completed if status == 'done'
  end

  def total_questions_answered
    return 0 if status == 'notstarted' || status == 'entered' || current_questiannair_question_id.nil?
    QuestionnaireQuestion.find(current_questiannair_question_id)[:order] - (status == 'in_process' ? 1 : 0)
  end

  def last_action(q_id)
    question_replies.where(questionnaire_id: q_id).try(:pluck, :updated_at).max
  end

  def gt_locale
    return :he if questionnaire.language.name == 'Hebrew'
    return :en
  end

  def reset_questionnaire
    update(current_questiannair_question_id: nil, status: 0)
    QuestionReply.where(questionnaire_id: questionnaire_id, questionnaire_participant_id: id).delete_all
  end

  def self.translate_status(stat)
    return 'Not Started' if stat == 'notstarted' || stat == 0
    return 'Entered'     if stat == 'entered'    || stat == 1
    return 'In Progress' if stat == 'in_process' || stat == 2
    return 'Completed'   if stat == 'completed'  || stat == 3
    return 'Unverified'   if stat == 'completed'  || stat == 4

    return 'NA'
  end

  def personal_report_map_image
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless') # Run in headless mode for servers
    options.add_argument("--window-size=11920,11080")

    driver = Selenium::WebDriver.for(:chrome, options: options)

    auth_token=JsonWebToken.encode({user_id: User.where(role:'super_admin').first.id, exp:  Time.now.to_i + 600})
    page_url=ENV['BACKEND_APP_URL']+"#/personal-map?token="+self.token+"&auth_token="+auth_token
    driver.navigate.to page_url
    puts("********************** personal_report_map_image:"+page_url)
    driver.save_screenshot('public/personal_report_images/personal_report_map_'+self.employee_id.to_s+'.png')
    wait = Selenium::WebDriver::Wait.new(timeout: 10) # timeout in seconds
    sleep(10)

    driver.save_screenshot('public/personal_report_images/personal_report_map_'+self.employee_id.to_s+'.png')

    driver.quit
  end

  def personal_report_org_map_image
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless') # Run in headless mode for servers
    driver = Selenium::WebDriver.for(:chrome, options: options)
    auth_token=JsonWebToken.encode({user_id: User.where(role:'super_admin').first.id, exp:  Time.now.to_i + 600})
    page_url=ENV['BACKEND_APP_URL']+"#/basic-map?qqid="+self.questionnaire.questionnaire_questions.where(is_funnel_question:true).first.id.to_s+"&auth_token="+auth_token+"&company_id="+self.employee.company_id.to_s
    puts("********************** personal_report_org_map_image:"+page_url)
    driver.navigate.to page_url
    wait = Selenium::WebDriver::Wait.new(timeout: 10) # timeout in seconds
    sleep(10)
    driver.save_screenshot('public/personal_report_images/personal_report_org_map_'+self.employee_id.to_s+'.png')
    
    driver.quit

  end

  #calculate the statistics for the personal report.
  #return a hash of data
  def personal_report_stats
    qqid=questionnaire.questionnaire_questions.where(is_funnel_question:true).first.id
    res={sum_connections:0,avg_connections:0,out_of_group_sum_connections:0,out_of_group_avg_connections:0,most_inbound_question:''}
    participant_connections=network_connections(qqid,false)
    res[:sum_connections]=participant_connections.map(&:id).count
    res[:avg_connections]=QuestionnaireParticipant.average_network_connections(qqid).round
    res[:out_of_group_sum_connections]=network_connections(qqid,true).map(&:id).count
    res[:out_of_group_avg_connections]=QuestionnaireParticipant.average_network_connections(qqid,true).round
    most_inbound_q=most_inbound_connections
    if most_inbound_connections
      res[:most_inbound_question]=ActionView::Base.full_sanitizer.sanitize(QuestionnaireQuestion.find(most_inbound_q).body)
    end
      return res
  end

  def network_connections(qqid, only_from_other_groups=false)
    question = QuestionnaireQuestion.find(qqid)
    emp_id = self.employee_id
    sid = question.questionnaire.snapshot_id
    nid = question.network_id
    cid = Employee.find(emp_id).company_id
    
    connections = NetworkSnapshotData
                   .select("from_employee_id AS id1, to_employee_id AS id2, value AS w")
                   .where(company_id: cid, snapshot_id: sid, network_id: nid)
                   .where("value > 0")
                   .where('from_employee_id=? OR to_employee_id=?', emp_id, emp_id)
    if only_from_other_groups
      connections = connections.joins("INNER JOIN employees AS e1 ON e1.id = network_snapshot_data.from_employee_id")
                                .joins("INNER JOIN employees AS e2 ON e2.id = network_snapshot_data.to_employee_id")
                                .where("e1.group_id != e2.group_id")
    end
  
    connections
  end

  #return the question where the user had the most inbounds
  def most_inbound_connections
    emp_id = self.employee_id
    # Assuming there's a direct association between employees and the companies they belong to
    cid = Employee.find(emp_id).company_id
  
    # First, find all questionnaire questions associated with the employee's company to limit the search
    # This is a broad assumption that questionnaire questions are somehow linked to companies
    qids = QuestionnaireQuestion.joins(:questionnaire)
                                .where(questionnaires: { company_id: cid })
                                .pluck(:id)
  
    # Next, find the questionnaire question where this employee has the highest number of inbound connections
    most_connections_qqid = NetworkSnapshotData
                              .where(to_employee_id: emp_id, questionnaire_question_id: qids)
                              .group(:questionnaire_question_id)
                              .order('COUNT(questionnaire_question_id) DESC')
                              .limit(1)
                              .pluck(:questionnaire_question_id)
                              .first
  
    # Return the QuestionnaireQuestion ID with the most inbound connections for this employee
    most_connections_qqid
  end
  
  

  def self.average_network_connections(qqid, only_from_other_groups=false)
    question = QuestionnaireQuestion.find(qqid)
    sid = question.questionnaire.snapshot_id
    nid = question.network_id
    cid = question.questionnaire.company_id
  
    base_query = NetworkSnapshotData
                  .where(company_id: cid, snapshot_id: sid, network_id: nid)
                  .where("value > 0")
  
    if only_from_other_groups
      # Include only connections between employees of different groups
      base_query = base_query.joins("INNER JOIN employees AS e1 ON e1.id = network_snapshot_data.from_employee_id")
                             .joins("INNER JOIN employees AS e2 ON e2.id = network_snapshot_data.to_employee_id")
                             .where("e1.group_id != e2.group_id")
    end
  
    # Aggregate connections per employee and calculate the average
    connection_counts = base_query
                        .group('from_employee_id')
                        .select('from_employee_id, COUNT(*) as connection_count')
                        .map(&:connection_count)
  
    # Calculate the average if there are any connections, else return 0 to indicate no connections
    if connection_counts.any?
      connection_counts.map(&:to_i).sum.to_f / connection_counts.size
    else
      0
    end
  end
  

  private

  def get_relevant_emps(dependent_question)
    return dependent_question.question_replies.where(questionnaire_participant_id: id, answer: true).pluck(:reffered_questionnaire_participant_id)
  end

  def find_questionnaire_question(_replies)
    return QuestionnaireQuestion.find(current_questiannair_question_id)
  end

end
