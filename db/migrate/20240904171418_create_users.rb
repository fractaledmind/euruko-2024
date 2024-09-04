class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :screen_name
      t.string :password_digest
      t.text :about
      t.datetime :last_seen_at

      t.timestamps
    end
    add_index :users, :screen_name, unique: true
  end
end
