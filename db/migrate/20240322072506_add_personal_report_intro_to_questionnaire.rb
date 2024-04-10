class AddPersonalReportIntroToQuestionnaire < ActiveRecord::Migration[6.1]
  def change
    add_column :questionnaires, :personal_report_intro, :text
  end
end
