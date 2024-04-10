class CreateAlgorithms < ActiveRecord::Migration[4.2]
  def change
    create_table :algorithms do |t|
      t.string 'name', null: false
      t.integer 'company_id', null: false
      t.timestamps
    end
  end
end
