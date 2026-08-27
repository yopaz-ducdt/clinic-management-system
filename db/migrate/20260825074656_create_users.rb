class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email
      t.string :encrypted_password
      t.string :role, null: false
      t.string :phone
      t.string :national_id
      t.string :status, null: false, default: "active"
      t.string :provider
      t.string :uid

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :national_id, unique: true
    add_index :users, [ :provider, :uid ], unique: true
  end
end
