require 'spec_helper'
include FactoryBot::Syntax::Methods
include InteractBackofficeActionsHelper
include InteractBackofficeHelper

describe QuestionnaireParticipant, type: :model do
  after do
    DatabaseCleaner.clean_with(:truncation)
  end

  describe 'filter_only_relevant_qp' do
    
    let(:emp) { create(:employee) }
    it 'should return automatically formed connections if configuration table says so' do
      CompanyConfigurationTable.create(key: 'populate_questionnaire_automatically', value: 'true', comp_id: 1)
      qp = QuestionnaireParticipant.create(employee_id: emp.id, questionnaire_id: 1)
      qq = QuestionnaireQuestion.create(company_id: 1, question_id: 1, questionnaire_id: 1)
      qp_arr = []
      (1..3).each do |id|
        new_qp = QuestionnaireParticipant.create(employee_id: id, questionnaire_id: 1)
        qp_arr << new_qp.id
        EmployeesConnection.create(employee_id: emp.id, connection_id: id)
      end
      expect(qp.filter_only_relevant_qp(qq)).to eq([1,2, 3, 4])
    end

    it 'should return participants who were picked in a question given one depends on' do
      qp = QuestionnaireParticipant.create(employee_id: emp.id)
      indep_qq = QuestionnaireQuestion.create(company_id: 1, question_id: 1, questionnaire_id: 1, order: 1)
      depen_qq = QuestionnaireQuestion.create(company_id: 1, question_id: 2, questionnaire_id: 1, order: 2, depends_on_question: indep_qq[:order])
      (11..13).each do |id|
        QuestionReply.create(
          questionnaire_question_id: indep_qq.id,
          questionnaire_id: 1,
          questionnaire_participant_id: qp.id,
          reffered_questionnaire_participant_id: id,
          answer: true
        )
      end
      expect(qp.filter_only_relevant_qp(depen_qq).length).to eq(3)
      expect(qp.filter_only_relevant_qp(depen_qq)).to include(11)
      expect(qp.filter_only_relevant_qp(depen_qq)).to include(12)
      expect(qp.filter_only_relevant_qp(depen_qq)).to include(13)
    end
  end

  describe 'update_questionnaire_participant_status' do
    it "should return in_process if equal  to 'in process'" do
      res = QuestionnaireParticipant.update_questionnaire_participant_status('in process', 2)
      expect(res).to be :in_process
    end

    it "should return entered if equal  to 'in process' and the current_question is  1" do
      res = QuestionnaireParticipant.update_questionnaire_participant_status('in process', 1)
      expect(res).to be :entered
    end

    it "should return completed if equal  to 'done'" do
      res = QuestionnaireParticipant.update_questionnaire_participant_status('done', 4)
      expect(res).to be :completed
    end

    it "should return entered if equal  to 'first time'" do
      res = QuestionnaireParticipant.update_questionnaire_participant_status('first time', 1)
      expect(res).to be :entered
    end

    it "should return entered is 'done' and number of questions is not 1 " do
      res = QuestionnaireParticipant.update_questionnaire_participant_status('done', 1, -1)
      expect(res).to be :entered
    end

    it "should return completed is 'done' and number of questions is 1 " do
      res = QuestionnaireParticipant.update_questionnaire_participant_status('done', 1, 1)
      expect(res).to be :completed
    end
  end

  describe 'update_replies' do
    before do
      @qp = QuestionnaireParticipant.new(questionnaire_id: 11)
      @r = [{ e_id: 1, answer: true }]
      @qp.stub(:find_questionnaire_question) { QuestionnaireQuestion.new(id: 22) }
    end

    it 'should create a new answer if none exists' do
      expect(QuestionReply.count).to be(0)
      @qp.update_replies(@r)
      expect(QuestionReply.count).to be(1)
      expect(QuestionReply.first[:answer]).to be(true)
    end

    it 'should not create a new answer if same one exists' do
      expect(QuestionReply.count).to be(0)
      @qp.update_replies(@r)
      expect(QuestionReply.count).to be(1)
      @qp.update_replies(@r)
      expect(QuestionReply.count).to be(1)
    end

    it 'should only change answer if new answer is different' do
      @qp.update_replies(@r)
      expect(QuestionReply.count).to be(1)
      @r = [{ e_id: 1, answer: false }]
      @qp.update_replies(@r)
      expect(QuestionReply.count).to be(1)
      expect(QuestionReply.first[:answer]).to be(false)
    end

    it 'should add a new record if does not exist' do
      @qp.update_replies(@r)
      expect(QuestionReply.count).to be(1)
      @r = [{ e_id: 2, answer: false }]
      @qp.update_replies(@r)
      expect(QuestionReply.count).to be(2)
    end

    it 'should create a new recored to reply when the questionnaire participant(e_id) not exist' do
      # @qp.update_attribute(:employee_id, 30)
      qp_for_employee_not_in_list = QuestionnaireParticipant.create!(questionnaire_id: @qp.questionnaire_id, employee_id: 30)
      r_without_qp = [{ employee_details_id: 30, e_id: nil, answer: true }]
      @qp.update_replies(r_without_qp)
      expect(QuestionReply.count).to be(1)
      expect(QuestionReply.last.reffered_questionnaire_participant_id).to be(qp_for_employee_not_in_list.id)
    end
  end

  describe 'test find_next_question' do
    before do
      @c   = Company.create!(name: 'Acme')
      @q   = Questionnaire.create!(name: "test", company_id: @c.id)
      @g1=Group.create(name: 'group_1', company_id: @company_id, snapshot_id: 1)
      @g2=Group.create(name: 'group_2', company_id: @company_id, snapshot_id: 1)
      @e1  = Employee.create!(company_id: @c.id, email: 'bb1@mail.com', first_name: 'Bb1', last_name: 'Qq1', external_id: 'bbb1')
      @e2  = Employee.create!(company_id: @c.id, email: 'bb2@mail.com', first_name: 'Bb2', last_name: 'Qq2', external_id: 'bbb2')
      @e3  = Employee.create!(company_id: @c.id, email: 'bb3@mail.com', first_name: 'Bb3', last_name: 'Qq3', external_id: 'bbb3')
      @qp1 = QuestionnaireParticipant.create(employee_id: @e1.id, questionnaire_id: @q.id)
      @qp2 = QuestionnaireParticipant.create(employee_id: @e2.id, questionnaire_id: @q.id)
      @qp3 = QuestionnaireParticipant.create(employee_id: @e3.id, questionnaire_id: @q.id)
    end

    describe 'with no dependent questions' do
      before(:each) do
        @qq1 = QuestionnaireQuestion.create!(company_id: 1, questionnaire_id: @q.id, network_id: 11, order: 1, min: 2, active: true)
        @qq2 = QuestionnaireQuestion.create!(company_id: 1, questionnaire_id: @q.id, network_id: 12, order: 2, min: 2, active: true)
        @qr2 = QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq1.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp2.id, answer: true)
        @qr3 = QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq2.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp2.id, answer: true)
      end

      it 'Should return the first question' do
        qq, status = @qp1.find_next_question
        expect( status ).to eq('in process')
        expect( qq.id ).to eq(1)
      end

      it 'Should return the second question' do
        QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq1.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp3.id, answer: true)
        qq, status = @qp1.find_next_question
        expect( status ).to eq('in process')
        expect( qq.id ).to eq(2)
      end

      it 'Should return done' do
        QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq1.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp3.id, answer: true)
        QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq2.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp3.id, answer: true)
        qq, status = @qp1.find_next_question
        expect( status ).to eq('done')
        expect( qq ).not_to be_nil
      end
    end

    describe 'with no dependent questions' do
      before(:each) do
        @qq1 = QuestionnaireQuestion.create!(company_id: 1, questionnaire_id: @q.id,                 order: 1, min: 2, active: true)
        @qq2 = QuestionnaireQuestion.create!(company_id: 1, questionnaire_id: @q.id, network_id: 12, order: 2,         active: true, depends_on_question: @qq1.id)
        @qr1 = QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq1.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp2.id, answer: true)
      end

      it 'Should return the first question' do
        qq, status = @qp1.find_next_question
        expect( status ).to eq('in process')
        expect( qq.id ).to eq(1)
      end

      it 'Should return the second, dependent, question in porcess' do
        QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq1.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp3.id, answer: true)
        qq, status = @qp1.find_next_question
        expect( status ).to eq('in process')
        expect( qq.id ).to eq(2)
      end

      it 'Should return the second, dependent, question in porcess even with one answer' do
        QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq1.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp3.id, answer: true)
        QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq2.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp2.id, answer: true)
        _, status = @qp1.find_next_question
        expect( status ).to eq('done')
      end

      it 'Should return done' do
        QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq1.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp3.id, answer: true)
        QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq2.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp2.id, answer: true)
        QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq2.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp3.id, answer: true)
        qq, status = @qp1.find_next_question
        expect( status ).to eq('done')
        expect( qq ).not_to be_nil
      end
    end
  end


  describe 'test presonal report stats' do
    before do
      AlgorithmType.find_or_create_by!(id: 1, name: 'measure')
      AlgorithmType.find_or_create_by!(id: 2, name: 'flag')
      AlgorithmType.find_or_create_by!(id: 3, name: 'analyze')
      AlgorithmType.find_or_create_by!(id: 4, name: 'group_measure')
      AlgorithmType.find_or_create_by!(id: 5, name: 'gauge')
      AlgorithmType.find_or_create_by!(id: 6, name: 'higher_gauge')
      AlgorithmType.find_or_create_by!(id: 8, name: 'interact_generic')
      AlgorithmType.find_or_create_by!(id: 9, name: 'company_statistic')
      AlgorithmType.find_or_create_by!(id: 10, name: 'internal_champion')
      AlgorithmType.find_or_create_by!(id: 11, name: 'isolated')
      AlgorithmType.find_or_create_by!(id: 12, name: 'connectors')
      AlgorithmType.find_or_create_by!(id: 13, name: 'bottlenecks')
      AlgorithmType.find_or_create_by!(id: 14, name: 'new_internal_champion')
      AlgorithmType.find_or_create_by!(id: 15, name: 'new_connectors')

      @c   = Company.create!(name: 'Acme')
      @q   = InteractBackofficeActionsHelper.create_new_questionnaire(@c.id)
      @g1=Group.create!(questionnaire_id:@q.id,name: 'group_1', company: @c, snapshot_id: 1)
      @g2=Group.create!(questionnaire_id:@q.id,name: 'group_2', company: @c, snapshot_id: 1,parent_group_id:@g1.id)
     
      @e1  = Employee.create!(group:@g1,company_id: @c.id, email: 'bb1@mail.com', first_name: 'Bb1', last_name: 'Qq1', external_id: 'bbb1')
      @e2  = Employee.create!(group:@g1,company_id: @c.id, email: 'bb2@mail.com', first_name: 'Bb2', last_name: 'Qq2', external_id: 'bbb2')
      @e3  = Employee.create!(group:@g2,company_id: @c.id, email: 'bb3@mail.com', first_name: 'Bb3', last_name: 'Qq3', external_id: 'bbb3')
      @qp1 = QuestionnaireParticipant.create(employee_id: @e1.id, questionnaire_id: @q.id)
      @qp2 = QuestionnaireParticipant.create(employee_id: @e2.id, questionnaire_id: @q.id)
      @qp3 = QuestionnaireParticipant.create(employee_id: @e3.id, questionnaire_id: @q.id)
    end

    describe 'number of connections for all groups' do
      before(:each) do
        @q1 = QuestionnaireQuestion.create!(title:'test 1',company_id: 1, questionnaire_id: @q.id, network_id: 11, order: 1, min: 2, active: true,is_funnel_question:true)
        @q2 = QuestionnaireQuestion.create!(title:'test 2',company_id: 1, questionnaire_id: @q.id, network_id: 11, order: 2, min: 2, active: true,is_funnel_question:false)
        
        @qq1=InteractBackofficeHelper.create_new_question(@c.id, @q.id,@q1, "test1",true)
        @qq2=InteractBackofficeHelper.create_new_question(@c.id, @q.id,@q2, "test2",false)
        
        @qr1 = QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq1.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp2.id, answer: true)
        @qr2 = QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq2.id, questionnaire_participant_id: @qp1.id, reffered_questionnaire_participant_id: @qp3.id, answer: true)
        
        @qr3 = QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq1.id, questionnaire_participant_id: @qp2.id, reffered_questionnaire_participant_id: @qp1.id, answer: true)
        @qr4 = QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq2.id, questionnaire_participant_id: @qp2.id, reffered_questionnaire_participant_id: @qp3.id, answer: true)
        
        @qr5 = QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq1.id, questionnaire_participant_id: @qp3.id, reffered_questionnaire_participant_id: @qp1.id, answer: true)
        @qr6 = QuestionReply.create!(questionnaire_id: @q.id, questionnaire_question_id: @qq2.id, questionnaire_participant_id: @qp3.id, reffered_questionnaire_participant_id: @qp2.id, answer: true)
        
        @q.update(state:5)
        Snapshot.create_snapshot_for_questionnaire(@c.id,Date.today.strftime('%Y-%m-%d'),@q.id)
        @q.freeze_questionnaire
      end

      it 'Should return the corrent number of connections' do
        expect( @qp1.network_connections(@qq1.id).count ).to eq(1)
        expect( @qp1.network_connections(@qq1.id).count ).to eq(1)
        expect( @qp1.network_connections(@qq1.id).count).to eq(1)
      end
    end

  end

  describe 'create_link' do
    it 'should create a legal link' do
      qp = QuestionnaireParticipant.new
      url = qp.create_link
      expect(url).to match(/^http.*questionnaire\?token=[0-9a-zA-Z]+$/)
    end
  end
end
