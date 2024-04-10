class CreateFriendships < ActiveRecord::Migration[4.2]
  def change
    create_table :friendships do |t|
      t.integer :employee_id, null: false
      t.integer :friend_id, null: false
      t.integer :friend_flag, default: 0

      t.timestamps
    end
    add_index :friendships, [:employee_id], name: 'index_friendships_on_employee_id'
    add_index :friendships, [:friend_id],   name: 'index_friendships_on_friend_id'
  end
end
