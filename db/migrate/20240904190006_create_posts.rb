class CreatePosts < ActiveRecord::Migration[7.2]
  def change
    create_table :posts do |t|
      t.belongs_to :user, null: false, foreign_key: true
      t.string :title, null: false, index: { unique: true }
      t.text :content

      t.timestamps
    end
  end
end
