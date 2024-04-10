require 'spec_helper'
require './spec/spec_factory'
include CompanyWithMetricsFactory

describe InteractBackofficeActionsHelper, type: :helper do
  before do
    Company.find_or_create_by(id: 1, name: "Hevra10")
    Snapshot.find_or_create_by(name: "2016-01", company_id: 1, timestamp: 3.weeks.ago)
    Group.find_or_create_by(name: "Root", company_id: 1, color_id: 10, external_id: '123' )
    Group.find_or_create_by(name: "R&D", company_id: 1, parent_group_id: 1, color_id: 10, external_id: '124')
    NetworkName.find_or_create_by!(name: "Communication Flow", company_id: 1)
    create_emps('moshe', 'acme.com', 5, {gid: 6})
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
    FactoryBot.reload
  end

  describe 'Copy questionnaire' do
    it 'should create a new questionnaire with a new snapshot' do
      InteractBackofficeActionsHelper.create_new_questionnaire(1)
      expect(Questionnaire.count).to eq(1)
      expect(Questionnaire.last.snapshot_id).to be > 1
      expect(Snapshot.count).to eq(2)
      expect(Group.count).to eq(4)
      expect(Employee.count).to eq(5)
    end
  end

  describe 'Rerun a questionnaire' do
    qid = -1
    before do
      InteractBackofficeActionsHelper.create_new_questionnaire(1)
      qid = Questionnaire.last.id
      (0..3).each do |i|
        QuestionnaireParticipant.create!(employee_id: i+1, questionnaire_id: qid, active: true)
        QuestionnaireQuestion.create!(company_id: 1, questionnaire_id: qid, network_id: i, order: i, active: true, title: "title-#{i}")
      end
    end

    it 'should create a copy of the questionnaire, and a new snapshot' do
      InteractBackofficeActionsHelper.create_new_questionnaire(1, qid, true)
      expect(Questionnaire.count).to eq(2)
      expect(Questionnaire.last.snapshot_id).to be > qid
      expect(Questionnaire.last.prev_questionnaire_id).to eq(qid)
      expect(Snapshot.count).to eq(3)
      expect(Group.count).to eq(6)
      expect(QuestionnaireParticipant.count).to eq(10)
      expect(QuestionnaireQuestion.count).to eq(8)
      expect(QuestionnaireQuestion.last.active).to be_truthy
    end

    it 'should have corrent questionnaire_id value' do
      sid = Questionnaire.last.snapshot_id
      qid = Questionnaire.last.id
      Group.where(snapshot_id: sid).last.update!(questionnaire_id: qid)
      InteractBackofficeActionsHelper.create_new_questionnaire(1, qid)
      expect(Group.last.questionnaire_id).to eq(Questionnaire.last.id)
    end

    describe 'with an existing questionnaire' do
      before do
        InteractBackofficeActionsHelper.create_new_questionnaire(1)
        qid = Questionnaire.last.id
        sid = Questionnaire.last.snapshot_id
        nid = NetworkName.last.id
        gid1 = Group.create!(name: "Root2", company_id: 1, color_id: 10, external_id: '1232', snapshot_id: sid, questionnaire_id: qid ).id
        gid2 = Group.create!(name: "R&D2", company_id: 1, parent_group_id: gid1, color_id: 10, external_id: '1242', snapshot_id: sid, questionnaire_id: qid).id
        FactoryBot.create(:employee, id: 10, group_id: gid2, snapshot_id: sid)
        FactoryBot.create(:employee, id: 11, group_id: gid2, snapshot_id: sid)
        QuestionnaireParticipant.create!(employee_id: 10, questionnaire_id: qid, active: true)
        QuestionnaireParticipant.create!(employee_id: 11, questionnaire_id: qid, active: true)
        QuestionnaireQuestion.create!(company_id: 1, questionnaire_id: qid, network_id: nid, order: 0, active: true, title: "title1")
        QuestionnaireQuestion.create!(company_id: 1, questionnaire_id: qid, network_id: nid, order: 0, active: true, title: "title2")
      end

      it 'should be able to duplicate questionnaire' do
        InteractBackofficeActionsHelper.create_new_questionnaire(1, qid, true)
        expect(Questionnaire.count).to eq(3)
      end

    end
  end

    describe 'Send SMS' do
      before do
        InteractBackofficeActionsHelper.create_new_questionnaire(1)
        qid = Questionnaire.last.id
        sid = Questionnaire.last.snapshot_id
        nid = NetworkName.last.id
        gid1 = Group.create!(name: "Root2", company_id: 1, color_id: 10, external_id: '1232', snapshot_id: sid, questionnaire_id: qid ).id
        gid2 = Group.create!(name: "R&D2", company_id: 1, parent_group_id: gid1, color_id: 10, external_id: '1242', snapshot_id: sid, questionnaire_id: qid).id
        FactoryBot.create(:employee, id: 10, group_id: gid2, snapshot_id: sid)
        FactoryBot.create(:employee, id: 11, group_id: gid2, snapshot_id: sid)
        QuestionnaireParticipant.create!(employee_id: 10, questionnaire_id: qid, active: true)
        QuestionnaireParticipant.create!(employee_id: 11, questionnaire_id: qid, active: true)
        QuestionnaireQuestion.create!(company_id: 1, questionnaire_id: qid, network_id: nid, order: 0, active: true, title: "title1")
        QuestionnaireQuestion.create!(company_id: 1, questionnaire_id: qid, network_id: nid, order: 0, active: true, title: "title2")
      end

      it 'should work with israeli phones and 019' do
       expect(InteractBackofficeActionsHelper.send_sms(Questionnaire.last,QuestionnaireParticipant.last, '0522656530')).to eq(['019',true])
       expect(InteractBackofficeActionsHelper.send_sms(Questionnaire.last,QuestionnaireParticipant.last, '+972522656530')).to eq(['019',true])

      end
      it 'should work with non-israeli phones and twilio' do
        expect(InteractBackofficeActionsHelper.send_sms(Questionnaire.last,QuestionnaireParticipant.last, '+10522656530')).to eq(['Twilio',true])
 
       end
 
      it 'should fail with an invalid phone number' do        
        expect(InteractBackofficeActionsHelper.send_sms(Questionnaire.last,QuestionnaireParticipant.last, '05226565300')).to eq(['019',false])
      end


    end
end
