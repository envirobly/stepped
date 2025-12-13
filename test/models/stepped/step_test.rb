require "test_helper"

class Stepped::StepTest < Stepped::TestCase
  setup do
    Temping.create "account" do
      with_columns do |t|
        t.string :name
      end

      stepped_action :action1

      def action1; end
    end

    Temping.create "car" do
      with_columns do |t|
        t.integer :honks, default: 0
      end

      def honk
        increment! :honks
      end
    end

    @account = Account.create!(name: "Acme Org")
    @car = Car.create!
  end

  test "HABTM" do
    actor = Car.create!
    parent_action = Stepped::Action.create!(name: "test", actor:, checksum_key: "a", concurrency_key: "a")
    step = parent_action.steps.create!(definition_index: 0)
    action = Stepped::Action.new(name: "test2", actor: Car.create!, checksum_key: "b", concurrency_key: "b")
    action.parent_steps << step
    assert action.save!
    assert_equal 1, action.parent_steps.count
    assert_equal step, action.parent_steps.first

    # copy_parent_steps_to
    action2 = Stepped::Action.create!(name: "test3", actor: Car.create!, checksum_key: "c", concurrency_key: "c")

    Stepped::Action.transaction do
      action.copy_parent_steps_to(action2)
      action.copy_parent_steps_to(action2)
      assert_equal 1, action2.parent_steps.size
      action2.update! name: "test4"
    end

    assert_equal 1, action2.parent_steps.count
    assert_equal step, action2.parent_steps.first
    assert_equal "test4", action2.name
  end

  test "NoPendingActionsError" do
    action = Stepped::Action.new(actor: @account, name: "action1")
    action.apply_definition
    step = action.steps.build(pending_actions_count: 0, definition_index: 0)
    action.save!

    assert_raises Stepped::Step::NoPendingActionsError do
      step.conclude_job
    end
  end

  test "wait" do
    Car.stepped_action :stopover do
      step do |step|
        step.wait 5.seconds
      end

      step do
        honk
      end
    end
    start_at = Time.zone.local 2024, 12, 12

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => +1
    ) do
      assert_enqueued_with(job: Stepped::WaitJob) do
        travel_to start_at do
          Stepped::ActionJob.perform_now @car, :stopover
        end
      end
    end

    action = Stepped::Action.last
    assert_predicate action, :performing?

    step = Stepped::Step.last
    assert_predicate step, :performing?
    assert_equal 1, step.pending_actions_count

    # Perform Stepped::WaitJob
    end_at = start_at + 6.seconds
    assert_difference("Stepped::Performance.count" => -1) do
      travel_to end_at do
        assert_equal 1, perform_enqueued_jobs(only: Stepped::WaitJob)
      end
    end

    assert_predicate action.reload, :succeeded?
    assert_predicate step.reload, :succeeded?
    assert_equal 0, step.pending_actions_count
  end

  test "failing deliberately within a step" do
    Car.stepped_action :soft_fail do
      step do
        honk
      end

      step do |step|
        step.status = :failed
      end

      step do
        honk
      end
    end

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +2,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      action = Stepped::ActionJob.perform_now @car, :soft_fail
      perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
      assert_predicate action.reload, :failed?
      assert_predicate Stepped::Step.last, :failed?
      assert_equal 1, @car.honks
    end
  end
end
