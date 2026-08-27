class CreateDoctors < ActiveRecord::Migration[8.1]
  def change
    create_table :doctors, id: :uuid do |t|
      t.references :user,
        null: false,
        foreign_key: true,
        type: :uuid,
        index: { unique: true }
      t.references :specialty, null: false, foreign_key: true, type: :uuid
      t.string :full_name, null: false
      t.text :bio
      t.datetime :deleted_at

      t.timestamps
    end
  end
end
