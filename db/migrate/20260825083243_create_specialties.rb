class CreateSpecialties < ActiveRecord::Migration[8.1]
  def change
    create_table :specialties, id: :uuid do |t|
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    add_index :specialties, :name
  end
end
