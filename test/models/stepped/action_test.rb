require "test_helper"

class Stepped::ActionTest < Stepped::TestCase
  setup do
    Temping.create "car" do
      with_columns do |t|
        t.integer :mileage, default: 0
        t.integer :honks, default: 0
        t.string :location
      end

      def drive(mileage)
        self.mileage += mileage
        save!
      end

      def honk
        increment! :honks
      end
    end

    @car = Car.create!
  end

  test "performing actor method without definition" do
    expected_time = Time.zone.local 2024, 12, 12
    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Performance.count" => 0
    ) do
      travel_to expected_time do
        Stepped::ActionJob.perform_now @car, :drive, 4
      end
    end

    action = Stepped::Action.last
    assert_equal @car, action.actor
    assert_equal "drive", action.name
    assert_nil action.checksum
    assert_equal "Car/#{@car.id}/drive", action.checksum_key
    assert_equal "Car/#{@car.id}/drive", action.concurrency_key
    assert_predicate action, :succeeded?
    assert_equal 0, action.current_step_index
    assert_equal expected_time, action.started_at
    assert_equal expected_time, action.completed_at
    assert action.root?
    assert_equal 4, @car.mileage
  end

  test "perform with steps" do
    Car.stepped_action :park do
      step do
        honk
      end

      step do |step, mileage|
        step.do :honk
        step.on [ self, nil ], :drive, mileage
      end

      succeeded do
        update! location: "garage"
      end
    end

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +2,
      "Stepped::Performance.count" => +1
    ) do
      assert_enqueued_with(job: Stepped::ActionJob) do
        Stepped::ActionJob.perform_now @car, :park, 5
      end
    end

    action_invoked_first = Stepped::Action.last
    assert_predicate action_invoked_first, :performing?
    assert_equal [ 5 ], action_invoked_first.arguments
    assert_equal 1, action_invoked_first.current_step_index
    assert_nil action_invoked_first.completed_at
    assert action_invoked_first.root?

    first_performance = Stepped::Performance.last
    assert_equal "Car/#{@car.id}/park", first_performance.concurrency_key
    assert_equal action_invoked_first, first_performance.action
    assert_equal 1, first_performance.actions.count
    assert_includes first_performance.actions, action_invoked_first
    assert_equal first_performance, action_invoked_first.performance

    assert_equal 1, @car.reload.honks
    assert_equal 2, action_invoked_first.steps.size

    step = action_invoked_first.steps.first
    assert_equal 0, step.pending_actions_count
    assert_equal 0, step.definition_index
    assert_predicate step, :succeeded?
    assert step.started_at
    assert step.completed_at

    step = action_invoked_first.steps.second
    assert_equal 1, step.definition_index
    assert_equal 2, step.pending_actions_count
    assert_predicate step, :performing?
    assert step.started_at
    assert_nil step.completed_at

    # Perform the same action again, with different arguments

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert_no_enqueued_jobs(only: Stepped::ActionJob) do
        Stepped::ActionJob.perform_now @car, :park, 7
      end
    end

    action_invoked_second = Stepped::Action.last
    assert_equal [ 7 ], action_invoked_second.arguments
    assert_predicate action_invoked_second, :pending?
    assert_equal 2, first_performance.reload.actions.count
    assert_equal "Car/#{@car.id}/park", first_performance.concurrency_key
    assert_equal action_invoked_first, first_performance.action
    assert_includes first_performance.actions, action_invoked_second
    assert_equal first_performance, action_invoked_second.performance

    assert_equal 1, @car.reload.honks

    # Perform first action second step actions

    assert_difference(
      "Stepped::Action.count" => +2,
      "Stepped::Step.count" => +4,
      "Stepped::Performance.count" => 0 # 2 are created and then destroyed
    ) do
      assert_enqueued_with(job: Stepped::ActionJob) do
        assert_equal 2, perform_enqueued_jobs(only: Stepped::ActionJob)
      end
    end

    assert_equal 1, action_invoked_first.reload.current_step_index

    step = action_invoked_first.steps.second
    assert_equal 2, step.actions.size
    assert_predicate step, :succeeded?
    assert step.completed_at
    step.actions.each do |action|
      assert_predicate action, :succeeded?
      assert action.completed_at
      assert_not action.root?
    end

    assert_predicate action_invoked_first, :succeeded?
    assert action_invoked_first.completed_at
    assert_equal 5, @car.reload.mileage
    assert_equal "garage", @car.location

    # Second invocation should be performing now
    assert_predicate action_invoked_second.reload, :performing?
    assert_equal 3, @car.reload.honks

    last_performance = Stepped::Performance.last
    assert_equal first_performance, last_performance
    assert_equal "Car/#{@car.id}/park", last_performance.concurrency_key

    # Complete the second action

    assert_difference(
      "Stepped::Action.count" => +2,
      "Stepped::Step.count" => +2,
      "Stepped::Performance.count" => -1
    ) do
      assert_no_enqueued_jobs(only: Stepped::ActionJob) do
        assert_equal 2, perform_enqueued_jobs(only: Stepped::ActionJob)
      end
    end

    assert_predicate action_invoked_second.reload, :succeeded?
    assert_equal 5 + 7, @car.reload.mileage
    assert_raises ActiveRecord::RecordNotFound do
      last_performance.reload
    end
  end

  test "passing active record objects as arguments and using `on` with multiple different actions" do
    skip "TODO"
  end

  test "modifying arguments in before block and checksum uses arguments modified in before block" do
    Car.stepped_action :multiplied_drive do
      before do |action, distance|
        action.arguments = [ distance * 2 ]
      end

      checksum do |distance|
        distance
      end

      step do |step, distance|
        step.do :drive, distance
      end
    end

    action = Stepped::ActionJob.perform_now @car, :multiplied_drive, 5
    assert_equal 1, perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
    assert_predicate action.reload, :succeeded?
    assert_equal [ 10 ], action.arguments
    assert_equal 10, @car.reload.mileage
    assert_equal Stepped.checksum(10), action.checksum
  end

  test "added arguments within a step are persisted" do
    Car.stepped_action :argument_add_in_step do
      step do |step|
        step.action.arguments.append 33
      end

      step do |step|
        step.do :drive, 2
      end

      step do |step, distance|
        drive distance
      end
    end

    action = Stepped::ActionJob.perform_now @car, :argument_add_in_step
    perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
    assert_predicate action.reload, :succeeded?
    assert_equal [ 33 ], action.arguments
    assert_equal 35, @car.reload.mileage
  end

  test "cancelling action in before block" do
    Car.stepped_action :cancelled_drive do
      before do |action|
        action.cancel
      end

      step do |step|
        throw "This should not be reached"
      end
    end

    assert_difference(
      "Stepped::Action.count" => 0,
      "Stepped::Step.count" => 0,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert_predicate Stepped::ActionJob.perform_now(@car, :cancelled_drive), :cancelled?
    end
  end

  test "cancelling nested action in before block completes parent step as failed" do
    Car.stepped_action :cancelled_drive do
      before do |action|
        action.cancel
      end

      step do |step|
        throw "This should not be reached"
      end
    end

    Car.stepped_action :failed_trip do
      step do |step|
        step.do :honk
        step.do :cancelled_drive
      end
    end

    parent_action = nil
    assert_difference(
      "Stepped::Action.count" => +2,
      "Stepped::Step.count" => +2,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      parent_action = Stepped::ActionJob.perform_now(@car, :failed_trip)

      assert_equal "failed_trip", parent_action.name
      assert_equal 1, parent_action.steps.size

      perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
    end

    assert_equal 1, @car.reload.honks
    assert_predicate parent_action.reload, :failed?
    assert_predicate parent_action.steps.last, :failed?
  end

  [ false, true ].each do |outbound|
    test "completing nested action (outbound: #{outbound}) in before block completes parent step as failed" do
      Car.stepped_action(:complete_early, outbound:) do
        before do |action|
          action.complete
        end

        step do |step|
          throw "This should not be reached"
        end
      end

      Car.stepped_action :trip do
        step do |step|
          step.do :honk
          step.do :complete_early
        end
      end

      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Step.count" => +1,
        "Stepped::Achievement.count" => 0,
        "Stepped::Performance.count" => +1
      ) do
        assert Stepped::ActionJob.perform_now(@car, :trip)
      end

      step = Stepped::Step.last
      assert_predicate step, :performing?
      assert_equal 2, step.pending_actions_count
      assert_equal 0, step.unsuccessful_actions_count

      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Step.count" => +1,
        "Stepped::Achievement.count" => 0,
        "Stepped::Performance.count" => -1
      ) do
        perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
      end

      assert_equal 1, @car.reload.honks

      assert_predicate step.reload, :succeeded?
      assert_equal 0, step.pending_actions_count
      assert_equal 0, step.unsuccessful_actions_count

      Stepped::Action.last(2).each do |action|
        assert_predicate action, :succeeded?
      end
    end
  end

  test "method call action that completes outbound" do
    Car.stepped_action :drive, outbound: true do
      after { honk }
    end

    action = Stepped::ActionJob.perform_now @car, :drive, 1
    assert_predicate action, :performing?

    Stepped::Performance.outbound_complete(@car, :drive)
    assert_equal 1, @car.reload.honks

    assert_predicate action, :performing?, "Still performing without reload"

    assert_nil Stepped::Performance.outbound_complete(@car, :drive, :failed)
    assert_equal 1, @car.reload.honks
    assert_predicate action.reload, :succeeded?
  end

  test "action on blank actor completes parent step" do
    Car.stepped_action :foo do
      step do |step|
        step.on nil, :bar
        step.on [], :bar
        step.on [ nil ], :bar
      end
    end
    action = nil
    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      action = Stepped::ActionJob.perform_now @car, :foo
      perform_enqueued_jobs(only: Stepped::ActionJob)
    end
    assert_predicate action.reload, :succeeded?
    assert_predicate action.steps.first, :succeeded?
  end

  test "adding after callbacks for an action that is not yet defined" do
    assert_nil Stepped::Registry.find(Car, :drive)

    Car.after_stepped_action :drive, :succeeded do |action, mileage|
      self.mileage += mileage
      save!
    end

    assert definition = Stepped::Registry.find(Car, :drive)

    Car.after_stepped_action :drive do |action, mileage|
      honk
    end

    assert_equal definition, Stepped::Registry.find(Car, :drive)

    action = Stepped::ActionJob.perform_now(@car, :drive, 30)
    assert_predicate action, :succeeded?
    assert_equal 60, @car.mileage
    assert_equal 1, @car.honks
    assert_equal 2, action.after_callbacks_succeeded_count
    assert_nil action.after_callbacks_failed_count
  end
end
