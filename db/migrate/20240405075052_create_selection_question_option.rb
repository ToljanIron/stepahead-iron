class CreateSelectionQuestionOption < ActiveRecord::Migration[6.1]
  def change
    create_table :selection_question_options do |t|
      t.string :name
      t.string :value
      t.integer :questionnaire_question_id

      t.timestamps
    end
  end
end
