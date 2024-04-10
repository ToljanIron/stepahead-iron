# frozen_string_literal: true
require 'oj'
require 'oj_mimic_json'
include QuestionnaireHelper
include InteractHelper

class QuestionnaireController < ApplicationController
  protect_from_forgery with: :exception, except:[:add_unverfied_participant,:participant_automcomplete,:get_question]
  before_action :authenticate_user, except: [:show_mobile,
                                             :all_employees,
                                             :all_groups,
                                             :get_next_question,
                                             :close_question,
                                             :update_question_replies,
                                             :keep_alive,
                                             :show_quest,
                                             :autosave,:add_unverfied_participant,:participant_automcomplete,:all_groups,:get_question,:personal_map_for_pdf]
  # before_action :set_locale


  def get_question
    authorize :application, :passthrough
    permitted = params.permit([:token,:q_num])
    q_num=sanitize_number(permitted[:q_num]).try(:to_i)||1
    token = sanitize_alphanumeric(permitted[:token])
    raise "No such token" if token.nil?
    qd=get_questionnaire_details(token)
    aq=Questionnaire.find(qd[:questionnaire_id])
    qp=QuestionnaireParticipant.find(qd[:qpid])
    qq=aq.questionnaire_questions[q_num-1]
    question=Questionnaire.find(qd[:questionnaire_id]).questionnaire_questions.where(order:q_num).first  
    qp.update!(current_questiannair_question_id: question.id)
    qd=get_questionnaire_details(token)
    qd[:answered]= QuestionReply.where(questionnaire_id: qd[:questionnaire_id],questionnaire_question_id: question.id,questionnaire_participant_id: qd[:qpid]).count

    res = Oj.dump(qd)
    render json: res
  end


  def all_employees
    authorize :application, :passthrough
    permitted = params.permit(:token)
    token = sanitize_alphanumeric(permitted[:token])
    raise "No such token" if token.nil?
    emps = hash_employees_of_company_by_token(token,false)
    if emps
      render json: emps, status: 200
    else
      render status: 500
    end
  end

  def all_groups
    authorize :application, :passthrough
    permitted = params.permit(:token)
    token = sanitize_alphanumeric(permitted[:token])
    raise "No such token" if token.nil?
    res=hash_groups_of_questionnaire_by_token(token,true)
    render plain: Oj.dump(res), status: 200
  end 


  
  def get_next_question
    authorize :application, :passthrough
    p = params.permit!
    token = sanitize_alphanumeric(params[:data][:token])
    raise "No such token" if token.nil?

    is_desktop = sanitize_boolean(params[:data][:desktop])
    is_desktop = true  if is_desktop == 'true'  || is_desktop == true
    is_desktop = false if is_desktop == 'false' || is_desktop == false

    res = get_questionnaire_details(token)
    reps = get_question_participants(token, res, is_desktop)
    res[:replies] = reps[:replies]
    res[:client_min_replies] = reps[:client_min_replies]
    res[:client_max_replies] = reps[:client_max_replies]
    res[:is_contain_funnel_question] = is_contain_funnel_question(token)
    res = Oj.dump(res)
    render json: res
  end

  def update_question_replies
    authorize :application, :passthrough
    p = params.permit!
    token = sanitize_alphanumeric(p[:data][:token])
    raise "No such token" if token.nil?
    qd = get_questionnaire_details(token)

    ## We defer sanitizing to the helper where we rely on ActiveRecord to do that
    update_replies(qd[:qpid], params[:data])
    res = Oj.dump({status: 'ok'})
    render json: res

  end

  def close_question
    authorize :application, :passthrough
    token = sanitize_alphanumeric(params[:data][:token])
    raise "No such token" if token.nil?
    qd = get_questionnaire_details(token)

    ## Update replies
    ## We defer sanitizing to the helper where we rely on ActiveRecord to do that
    update_replies(qd[:qpid], params[:data])

    msg = close_questionnaire_question(qd)

    res = (msg.nil? ? {status: 'ok'} : {status: 'fail', reason: msg});
    res = Oj.dump(res)
    render json: res
  end

  def add_unverfied_participant
    
    authorize :application, :passthrough
    token = sanitize_alphanumeric(params[:token])
   raise "No such token" if token.nil?
    permitted = request.params
    
    res=Questionnaire.create_unverified_participant_employee(permitted)
    
    unv_employee=res[:employee]
    unv_participant_id=res[:qpid]
    res = (res[:msg].empty? ? {status: 'ok',e_id:unv_employee.id, name:[unv_employee.first_name,unv_employee.last_name].join(" "),qpid:unv_participant_id, image_url:nil}: {status: 'fail', reason: msg});
    res = Oj.dump(res)
    
    render json: res
  end

  def participant_automcomplete
    
    authorize :application, :passthrough
    @token = (sanitize_alphanumeric(params[:token]))
    qd = get_questionnaire_details(@token)
     
    qps_emp_ids=Questionnaire.find(qd[:questionnaire_id]).questionnaire_participant.where.not(employee_id: -1).pluck(:employee_id)
    puts('+_+_+_+_+_+_+_+_+_+_+_+_+__+_+_+_'+qps_emp_ids.to_s)

    if qps_emp_ids
      #field name
      field=params[:field]=='l' ? :last_name   :  :first_name
      puts('+_+_+_+_+_+_+_+_+_+_+_+_+__+_+_+_'+qps_emp_ids.to_s)
      
      res= Employee.where(id:qps_emp_ids).where("LOWER(#{field}) like ? ","%#{params[:term].downcase}%").pluck(field).uniq
      
      render json: { data: res}, status: 200

    end
  end

  def show_home
    goto_home
    redirect_to ''
  end


  def show_quest
    if params['desktop'] == 'true'
      show_desktop
    else
      show_mobile
    end
  end

  def show_mobile
    @token = JSON.parse(params[:data])['token']
    employee = Employee.find_by(token: @token)
    if employee
      @name = employee.first_name
      render 'mobile'
    else
      puts "Did not manage to find employee from token: #{@token}"
      render plain: 'Failed to load app, unkown employee.'
    end
  end

  def show_desktop
    @token = JSON.parse(params[:data])['token']
    employee = Employee.find_by(token: @token)
    if employee
      @name = employee.first_name
      render 'desk'
    else
      puts "Did not manage to find employee from token: #{@token}"
      render plain: 'Failed to load app, unkown employee.'
    end
  end

  def keep_alive
    authorize :application, :passthrough
    permitted = params.permit(:counter)
    counter = permitted[:counter]
    render json: { alive: counter }, status: 200
  end

  ###############################################
  # Get everything needed to draw an explore map
  ###############################################
  def personal_map_for_pdf
    authorize :application, :passthrough
    permitted = params.permit([:token])
    token = sanitize_alphanumeric(permitted[:token])

    qd=get_questionnaire_details(token)
    
    employee = QuestionnaireParticipant.find(qd[:qpid]).employee
    quest=Questionnaire.find(qd[:questionnaire_id])
   
    if employee ==nil
      puts "Did not manage to find employee from token: #{@token}"
      render plain: 'Failed to load report, unkown employee.'
    end
    
    qq=quest.questionnaire_questions.where(is_funnel_question:true).first
    user_map = employee.id
    qqid = qq.id
    gids=nil
    cid = employee.company_id
   
    quest = qq.questionnaire
    #authorize quest, :viewer?
    nid = qq.network_id
    sid = quest.snapshot_id
    if (gids.nil? || gids == [] || gids == '')
      gids = Group
               .by_snapshot(sid)
               .where(questionnaire_id: quest.id)
               .pluck(:id).join(',')
    end

    cm = CompanyMetric.where(network_id: nid, algorithm_id: 601).last
    cmid = cm ? cm.id : nil

    groups = Group
      .select("groups.id AS gid, name, parent_group_id AS parentId, color_id")
      .where(snapshot_id: sid)
      .where("groups.id in (#{gids})")
    nodes = Employee
      .select("employees.id AS id, first_name || ' ' || last_name AS t, employees.group_id, g.name AS gname,
               cms.score AS d, rank_id, gender, ro.name AS role_name, o.name AS office_name,
               jt.name AS job_title_name, g.color_id, 
               fa.name as param_a,
               fb.name as param_b,
               fc.name as param_c,
               fd.name as param_d,
               fe.name as param_e,
               ff.name as param_f,
               fg.name as param_g,
               employees.factor_h as param_h,
               employees.factor_i as param_i,
               employees.factor_j as param_j")
      .joins("JOIN groups AS g ON g.id = employees.group_id")
      .joins("JOIN cds_metric_scores as cms ON cms.employee_id = employees.id")
      .joins("LEFT JOIN roles AS ro ON ro.id = employees.role_id")
      .joins("LEFT JOIN offices AS o ON o.id = employees.office_id")
      .joins("LEFT JOIN job_titles as jt ON jt.id = employees.job_title_id")
      .joins("LEFT JOIN factor_as as fa ON fa.id = employees.factor_a_id")
      .joins("LEFT JOIN factor_bs as fb ON fb.id = employees.factor_b_id")
      .joins("LEFT JOIN factor_cs as fc ON fc.id = employees.factor_c_id")
      .joins("LEFT JOIN factor_ds as fd ON fd.id = employees.factor_d_id")
      .joins("LEFT JOIN factor_es as fe ON fe.id = employees.factor_e_id")
      .joins("LEFT JOIN factor_fs as ff ON ff.id = employees.factor_f_id")
      .joins("LEFT JOIN factor_gs as fg ON fg.id = employees.factor_g_id")
      .where("employees.is_verified = ?",true)
      .where("employees.company_id = ? AND employees.snapshot_id = ? AND cms.company_metric_id = ?", cid, sid, cmid)
      .where("employees.group_id in (#{gids})" )

    eids = nodes.map { |n| n.id }
    c_factor_names = CompanyFactorName.where(company_id: cid, snapshot_id: sid)
    factor_names = {}
    c_factor_names.each do |f|
      factor_names[f.factor_name.camelize] = (!f.display_name.blank? ? f.display_name : f.factor_name.camelize)
    end
    if(user_map && eids.include?(user_map))
      links = NetworkSnapshotData
        .select("from_employee_id AS id1, to_employee_id AS id2, value AS w")
        .where(company_id: cid, snapshot_id: sid, network_id: nid)
        .where("value > 0")
        .where('from_employee_id=? OR to_employee_id=?', user_map, user_map)
      nodes = top_indegree_unconnected_nodes(links,nodes)
    else
      links = NetworkSnapshotData
        .select("from_employee_id AS id1, to_employee_id AS id2, value AS w")
        .where(company_id: cid, snapshot_id: sid, network_id: nid)
        .where("value > 0")
        .where(from_employee_id: eids)
        .where(to_employee_id: eids)
    end
    res = {
      groups: groups,
      nodes: nodes,
      links: links,
      department: nil,
      questionnaireName: quest.name,
      questionTitle: qq.title,
      factorNames: factor_names
    }
    
    res = Oj.dump(res)
   
    render json: res
  end
  private

  # def set_locale
  #   I18n.locale = :iw
  # end

  def goto_home
    @curr_page = PAGES[:home]
  end

  def authenticate_user
    redirect_to signin_path unless  logged_in?
  end
 
  def set_locale(extract_locale= :en)
    I18n.locale = extract_locale || :en
  end
end
