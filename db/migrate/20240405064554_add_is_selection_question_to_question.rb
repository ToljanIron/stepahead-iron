class AddIsSelectionQuestionToQuestion < ActiveRecord::Migration[6.1]
  def change
    add_column :questionnaire_questions, :is_selection_question, :boolean, default: false
  end
end
