# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_25_090751) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "doctors", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "bio"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "full_name", null: false
    t.uuid "specialty_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["specialty_id"], name: "index_doctors_on_specialty_id"
    t.index ["user_id"], name: "index_doctors_on_user_id", unique: true
  end

  create_table "patients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "address"
    t.datetime "created_at", null: false
    t.date "date_of_birth"
    t.datetime "deleted_at"
    t.string "full_name", null: false
    t.string "gender", null: false
    t.uuid "managed_by_user_id", null: false
    t.string "national_id"
    t.string "relationship", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_patients_on_deleted_at"
    t.index ["managed_by_user_id"], name: "index_patients_on_managed_by_user_id"
    t.index ["national_id"], name: "index_patients_on_national_id", unique: true
  end

  create_table "specialties", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_specialties_on_name"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "encrypted_password"
    t.string "national_id"
    t.string "phone"
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", null: false
    t.string "status", default: "active", null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["national_id"], name: "index_users_on_national_id", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "doctors", "specialties"
  add_foreign_key "doctors", "users"
  add_foreign_key "patients", "users", column: "managed_by_user_id"
end
