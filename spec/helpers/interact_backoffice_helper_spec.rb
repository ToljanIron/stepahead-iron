require 'spec_helper'
require './spec/spec_factory'
require './app/helpers/line_processing_context.rb'
require './app/helpers/import_data_helper.rb'
require 'rubyXL/convenience_methods'

include CompanyWithMetricsFactory
include ImportDataHelper

describe InteractBackofficeHelper, type: :helper do
  before do
    Company.find_or_create_by(id: 1, name: "Hevra10")
    Snapshot.find_or_create_by(name: "2016-01", company_id: 1, timestamp: 3.weeks.ago)
    g0 = Group.find_or_create_by(name: "Root", company_id: 1, color_id: 10, external_id: '123' )
    g1 = Group.find_or_create_by(name: "L2-1", company_id: 1, parent_group_id: g0.id, color_id: 10, external_id: '124')
    g2 = Group.find_or_create_by(name: "L2-2", company_id: 1, parent_group_id: g0.id, color_id: 10, external_id: '125')
    Group.find_or_create_by(name: "L3-1", company_id: 1, parent_group_id: g1.id, color_id: 10, external_id: '126')
    Group.find_or_create_by(name: "L3-2", company_id: 1, parent_group_id: g1.id, color_id: 10, external_id: '127')
    Group.find_or_create_by(name: "L3-3", company_id: 1, parent_group_id: g2.id, color_id: 10, external_id: '128')
    create_emps('moshe', 'acme.com', 5, {gid: 6})

    e1 = Employee.find_or_create_by(company_id: Company.first.id, email: 'bb1@mail.com', first_name: 'Bb1', last_name: 'Qq1', external_id: 'bbb1')
    e2 = Employee.find_or_create_by(company_id: Company.first.id, email: 'bb2@mail.com', first_name: 'Bb2', last_name: 'Qq2', external_id: 'bbb2')
    
    q = Questionnaire.create!(name: "test", company_id: Company.first.id, state: 'sent', is_snowball_q:true)
   
    
    qp1 = QuestionnaireParticipant.find_or_create_by(employee_id: e1.id, questionnaire_id: q.id, active: true, token: 't1')
    qp1 = QuestionnaireParticipant.find_or_create_by(employee_id: e2.id, questionnaire_id: q.id, active: true, token: 't2')
 
    qq1 = QuestionnaireQuestion.find_or_create_by(company_id: 1, questionnaire_id: q.id, network_id: 11, active: true, order: 1, min: 2, max: 4)
    qq2 = QuestionnaireQuestion.find_or_create_by(company_id: 1, questionnaire_id: q.id, network_id: 12, active: true, order: 2)
    qq3 = QuestionnaireQuestion.find_or_create_by(company_id: 1, questionnaire_id: q.id, network_id: 13, active: true, order: 3)

  end

  after do
    DatabaseCleaner.clean_with(:truncation)
    FactoryBot.reload
  end

  describe 'create_employee' do
    it 'should update the field questionnaire_id in the group and all ancestors' do
     InteractBackofficeActionsHelper.create_new_questionnaire(1)
      p = {
        'first_name' => 'f',
        'last_name' => 'l',
        'email' => 'mail@qqq.com',
        'phone' => '052-2233445',
        'group_name' => 'L3-1'
      }
      InteractBackofficeHelper.create_employee(1, p, Questionnaire.last)
      expect(Group.find_by(name: 'L3-1', snapshot_id: 2).questionnaire_id).to eq(2)
      expect(Group.find_by(name: 'L2-1', snapshot_id: 2).questionnaire_id).to eq(2)
      expect(Group.find_by(name: 'Root', snapshot_id: 2).questionnaire_id).to eq(2)
    end
  end

  describe 'update_employee' do
    it 'changing an employees group should update questionnaire_id in relevant groups' do
      InteractBackofficeActionsHelper.create_new_questionnaire(1)
      p = {
        'first_name' => 'f',
        'last_name' => 'l',
        'email' => 'mail@qqq.com',
        'phone' => '052-2233445',
        'group_name' => 'L3-1'
      }
      InteractBackofficeHelper.create_employee(1, p, Questionnaire.last)
      p['group_name'] = 'L3-3'
      p['id'] = Employee.last.id
      InteractBackofficeHelper.update_employee(1, p, Questionnaire.last.id)

      expect(Group.find_by(name: 'L3-1', snapshot_id: 2).questionnaire_id).to be_nil
      expect(Group.find_by(name: 'L2-1', snapshot_id: 2).questionnaire_id).to be_nil
      expect(Group.find_by(name: 'L3-3', snapshot_id: 2).questionnaire_id).to eq(2)
      expect(Group.find_by(name: 'L2-2', snapshot_id: 2).questionnaire_id).to eq(2)
      expect(Group.find_by(name: 'Root', snapshot_id: 2).questionnaire_id).to eq(2)
    end

  end

  describe 'validate employee' do
    it 'works' do
      InteractBackofficeActionsHelper.create_new_questionnaire(1)
      p = {
        'first_name' => 'f',
        'last_name' => 'l',
        'email' => 'mail1@qqq.com',
        'phone' => '052-2233445',
        'group_name' => 'L3-1',
        'is_verified'=>false
      }
      
      InteractBackofficeHelper.create_employee(1, p, Questionnaire.last)
      num_qps=QuestionnaireParticipant.count
      expect(Employee.last.is_verified).to eq(false)
      xls=InteractBackofficeHelper.download_employees(1,Employee.last.snapshot_id,'unverified')

      validate_unverified_by_excel_sheet(1,File.open('./tmp/'+xls), Questionnaire.last.id)
      expect(Employee.last.is_verified).to eq(true)
      expect(num_qps).to eq(QuestionnaireParticipant.count)
    end
  
    it 'works when changing unverified employee group' do
      InteractBackofficeActionsHelper.create_new_questionnaire(1)
      p = {
        'first_name' => 'f',
        'last_name' => 'l',
        'email' => 'mail1@qqq.com',
        'phone' => '052-2233445',
        'group_name' => 'L2-1',
        'is_verified'=>false
      }
      new_group='L3-1'
      InteractBackofficeHelper.create_employee(1, p, Questionnaire.last)
      num_qps=QuestionnaireParticipant.count
      expect(Employee.last.is_verified).to eq(false)
      expect(Employee.count).to eq(13)
      xls=InteractBackofficeHelper.download_employees(1,Employee.last.snapshot_id,'unverified')
      workbook = RubyXL::Parser.parse('./tmp/'+xls)
      workbook[0][1][9].change_contents(new_group) # Sets different group
      workbook.save
      validate_unverified_by_excel_sheet(1,File.open('./tmp/'+xls), Questionnaire.last.id)
      expect(Employee.count).to eq(13)
      expect(Employee.last.is_verified).to eq(true)
      expect(Employee.last.group.name).to eq(new_group)
    end
    it 'works when deleting an unverified employee ' do
      InteractBackofficeActionsHelper.create_new_questionnaire(1)
      p = {
        'first_name' => 'f',
        'last_name' => 'l',
        'email' => 'mail1@qqq.com',
        'phone' => '052-2233445',
        'group_name' => 'L2-1',
        'is_verified'=>false
      }
      InteractBackofficeHelper.create_employee(1, p, Questionnaire.last)
     
      num_qps=QuestionnaireParticipant.count
      expect(Employee.last.is_verified).to eq(false)
      expect(Employee.count).to eq(13)
      last_employee_id=Employee.last.id
      xls=InteractBackofficeHelper.download_employees(1,Employee.last.snapshot_id,'unverified')
      workbook = RubyXL::Parser.parse('./tmp/'+xls)
      workbook[0].add_cell(1,22,'D') # Sets delete command
      workbook.save
      
      validate_unverified_by_excel_sheet(1,File.open('./tmp/'+xls), Questionnaire.last.id)
      expect(Employee.count).to eq(12)
      expect(Employee.last.id).not_to eq(last_employee_id)
    end
    it 'works when merging employees' do
      
      #creating an unverified employee
      
      unverified_qp={
        :e_first_name => 'f',
        :e_last_name => 'l',
        :qpid=>QuestionnaireParticipant.first.id,
        :e_group=>Group.first.id
      }
      add_unverified_qp_result=Questionnaire.create_unverified_participant_employee(unverified_qp)
      
      expect(Employee.count).to eq(8)
      
      expect(QuestionnaireParticipant.count).to eq(3)
      expect(Employee.last.is_verified).to eq(false)
      
      xls=InteractBackofficeHelper.download_employees(1,Employee.last.snapshot_id,'unverified')
      workbook = RubyXL::Parser.parse('./tmp/'+xls)
      workbook[0].add_cell(1,22,'M') # Sets merge command
      workbook[0].add_cell(1,23,'bbb2') # Sets id to merge with
    
      workbook.save
      #create an answer that points to the unverified participant
      QuestionReply.create!(questionnaire_id:Questionnaire.last.id,questionnaire_question_id:QuestionnaireQuestion.first.id,questionnaire_participant_id:Employee.first.id,reffered_questionnaire_participant_id:add_unverified_qp_result[:qpid],answer:true)
      validate_unverified_by_excel_sheet(1,File.open('./tmp/'+xls), Questionnaire.last.id)
      
      expect(Employee.count).to eq(7)
      expect(QuestionReply.last.reffered_questionnaire_participant_id).to eq(QuestionnaireParticipant.last.id)
      expect(QuestionnaireParticipant.count).to eq(2)

      end
  end
end
