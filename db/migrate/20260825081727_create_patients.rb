class CreatePatients < ActiveRecord::Migration[8.1]
  def change
    create_table :patients, id: :uuid do |t|
      t.references :managed_by_user,
        null: false,
        foreign_key: { to_table: :users },
        type: :uuid
      t.string :national_id
      t.string :relationship, null: false
      t.string :full_name, null: false
      t.date :date_of_birth
      t.string :gender, null: false
      t.string :address
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :patients, :national_id, unique: true
    add_index :patients, :deleted_at
  end
end
