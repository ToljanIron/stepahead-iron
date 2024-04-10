class CreateSeniorities < ActiveRecord::Migration[4.2]
  def change
    create_table :seniorities do |t|
      t.string :name
      t.integer :color_id
      t.timestamps null: false
    end
    add_index :seniorities, [:name], unique: true
  end
end
