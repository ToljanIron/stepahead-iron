class AddPersonalReportEmailSubjectToQuestionnaire < ActiveRecord::Migration[6.1]
  def change
    add_column :questionnaires, :personal_report_email_subject, :string
  end
end
