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

ActiveRecord::Schema[8.1].define(version: 2025_12_14_104829) do
  create_table "stepped_achievements", force: :cascade do |t|
    t.string "checksum", null: false
    t.string "checksum_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["checksum_key"], name: "index_stepped_achievements_on_checksum_key", unique: true
  end

  create_table "stepped_actions", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.string "actor_type", null: false
    t.integer "after_callbacks_failed_count"
    t.integer "after_callbacks_succeeded_count"
    t.json "arguments"
    t.string "checksum"
    t.string "checksum_key", null: false
    t.datetime "completed_at"
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.integer "current_step_index", default: 0, null: false
    t.string "job"
    t.string "name", null: false
    t.boolean "outbound", default: false, null: false
    t.bigint "performance_id"
    t.boolean "root", default: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "timeout_seconds"
    t.datetime "updated_at", null: false
    t.index ["actor_type", "actor_id"], name: "index_stepped_actions_on_actor"
    t.index ["performance_id", "outbound"], name: "index_stepped_actions_on_performance_id_and_outbound"
    t.index ["performance_id"], name: "index_stepped_actions_on_performance_id"
    t.index ["root"], name: "index_stepped_actions_on_root"
  end

  create_table "stepped_actions_steps", id: false, force: :cascade do |t|
    t.bigint "action_id", null: false
    t.bigint "step_id", null: false
    t.index ["action_id", "step_id"], name: "index_stepped_actions_steps_on_action_id_and_step_id", unique: true
    t.index ["step_id", "action_id"], name: "index_stepped_actions_steps_on_step_id_and_action_id"
  end

  create_table "stepped_actors", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "stepped_performances", force: :cascade do |t|
    t.bigint "action_id", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.string "outbound_complete_key"
    t.datetime "updated_at", null: false
    t.index ["action_id"], name: "index_stepped_performances_on_action_id", unique: true
    t.index ["concurrency_key"], name: "index_stepped_performances_on_concurrency_key", unique: true
    t.index ["outbound_complete_key"], name: "index_stepped_performances_on_outbound_complete_key", where: "(outbound_complete_key IS NOT NULL)"
  end

  create_table "stepped_steps", force: :cascade do |t|
    t.bigint "action_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "definition_index", null: false
    t.integer "pending_actions_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "unsuccessful_actions_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["action_id", "definition_index"], name: "index_stepped_steps_on_action_id_and_definition_index", unique: true
    t.index ["action_id"], name: "index_stepped_steps_on_action_id"
  end

  add_foreign_key "stepped_actions", "stepped_performances", column: "performance_id"
  add_foreign_key "stepped_performances", "stepped_actions", column: "action_id"
  add_foreign_key "stepped_steps", "stepped_actions", column: "action_id"
end
