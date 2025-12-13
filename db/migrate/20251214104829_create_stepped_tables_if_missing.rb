class CreateSteppedTablesIfMissing < ActiveRecord::Migration[8.0]
  def change
    create_table :stepped_achievements, if_not_exists: true do |t|
      t.string :checksum, null: false
      t.string :checksum_key, null: false
      t.timestamps null: false
    end
    add_index :stepped_achievements, :checksum_key, unique: true, if_not_exists: true

    create_table :stepped_actions, if_not_exists: true do |t|
      t.bigint :actor_id, null: false
      t.string :actor_type, null: false
      t.integer :after_callbacks_failed_count
      t.integer :after_callbacks_succeeded_count
      t.json :arguments
      t.string :checksum
      t.string :checksum_key, null: false
      t.datetime :completed_at
      t.string :concurrency_key, null: false
      t.integer :current_step_index, null: false, default: 0
      t.string :job
      t.string :name, null: false
      t.boolean :outbound, null: false, default: false
      t.bigint :performance_id
      t.boolean :root, default: false
      t.datetime :started_at
      t.string :status, null: false, default: "pending"
      t.integer :timeout_seconds
      t.timestamps null: false
    end

    add_index :stepped_actions, %i[actor_type actor_id], name: "index_stepped_actions_on_actor", if_not_exists: true
    add_index :stepped_actions, %i[performance_id outbound], name: "index_stepped_actions_on_performance_id_and_outbound", if_not_exists: true
    add_index :stepped_actions, :performance_id, if_not_exists: true
    add_index :stepped_actions, :root, if_not_exists: true

    create_table :stepped_actions_steps, id: false, if_not_exists: true do |t|
      t.bigint :action_id, null: false
      t.bigint :step_id, null: false
    end

    add_index :stepped_actions_steps, %i[action_id step_id], unique: true, name: "index_stepped_actions_steps_on_action_id_and_step_id", if_not_exists: true
    add_index :stepped_actions_steps, %i[step_id action_id], name: "index_stepped_actions_steps_on_step_id_and_action_id", if_not_exists: true

    create_table :stepped_actors, if_not_exists: true do |t|
      t.text :content
      t.timestamps null: false
    end

    create_table :stepped_performances, if_not_exists: true do |t|
      t.bigint :action_id, null: false
      t.string :concurrency_key
      t.string :outbound_complete_key
      t.timestamps null: false
    end

    add_index :stepped_performances, :action_id, unique: true, name: "index_stepped_performances_on_action_id", if_not_exists: true
    add_index :stepped_performances, :concurrency_key, unique: true, name: "index_stepped_performances_on_concurrency_key", if_not_exists: true
    add_index :stepped_performances, :outbound_complete_key,
              name: "index_stepped_performances_on_outbound_complete_key",
              where: "(outbound_complete_key IS NOT NULL)",
              if_not_exists: true

    create_table :stepped_steps, if_not_exists: true do |t|
      t.bigint :action_id, null: false
      t.datetime :completed_at
      t.integer :definition_index, null: false
      t.integer :pending_actions_count, null: false, default: 0
      t.datetime :started_at
      t.string :status, null: false, default: "pending"
      t.integer :unsuccessful_actions_count, default: 0
      t.timestamps null: false
    end

    add_index :stepped_steps, %i[action_id definition_index], unique: true, name: "index_stepped_steps_on_action_id_and_definition_index", if_not_exists: true
    add_index :stepped_steps, :action_id, name: "index_stepped_steps_on_action_id", if_not_exists: true

    add_foreign_key :stepped_actions, :stepped_performances, column: :performance_id, if_not_exists: true
    add_foreign_key :stepped_performances, :stepped_actions, column: :action_id, if_not_exists: true
    add_foreign_key :stepped_steps, :stepped_actions, column: :action_id, if_not_exists: true
  end
end
