require "test_helper"

class Stepped::ActionCompletesOutboundTest < Stepped::TestCase
  setup do
    Temping.create "car" do
      with_columns do |t|
        t.string :location
        t.integer :mileage, default: 0
      end

      stepped_action :visit do
        step do |step, distance, location|
          step.do :drive, distance
        end

        step do |step, distance, location|
          step.do :change_location, location
        end
      end

      stepped_action :drive, outbound: true do
        after :cancelled, :failed, :timed_out do
          drive 1
        end
      end

      def drive(mileage)
        self.mileage += mileage
        save!
      end

      def change_location(location)
        update!(location:)
      end
    end

    @car = Car.create!
  end

  test "performing direct action that completes successfully outbound" do
    action =
      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Step.count" => +1,
        "Stepped::Achievement.count" => 0,
        "Stepped::Performance.count" => +1
      ) do
        Stepped::ActionJob.perform_now @car, :drive, 11
      end

    assert_predicate action, :performing?
    assert_predicate action, :outbound?
    assert_equal @car, action.actor
    assert_equal "drive", action.name
    assert_equal [ 11 ], action.arguments
    assert action.started_at
    assert_nil action.completed_at
    assert_equal 0, action.current_step_index
    assert_equal 11, @car.reload.mileage

    assert_difference(
      "Stepped::Action.count" => 0,
      "Stepped::Step.count" => 0,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => -1
    ) do
      Stepped::Performance.outbound_complete @car, :drive
    end

    assert_predicate action.reload, :succeeded?
    assert action.completed_at
    assert action.started_at < action.completed_at
  end

  %w[ cancelled failed timed_out ].each do |status|
    test "completing outbound action as #{status} with an after callback" do
      action = Stepped::ActionJob.perform_now @car, :drive, 11
      assert_equal 11, @car.reload.mileage

      assert_difference(
        "Stepped::Action.count" => 0,
        "Stepped::Step.count" => 0,
        "Stepped::Achievement.count" => 0,
        "Stepped::Performance.count" => -1
      ) do
        Stepped::Performance.outbound_complete @car, :drive, status
      end

      assert_equal status, action.reload.status
      assert action.completed_at
      assert action.started_at < action.completed_at
      assert_equal 12, @car.reload.mileage
    end
  end

  test "performing action that completes outbound as nested action" do
    action = Stepped::ActionJob.perform_now @car, :visit, 100, "London"
    assert_equal 1, perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
    assert_predicate action.reload, :performing?
    assert_not_predicate action, :outbound?
    action.steps.each do |step|
      assert_predicate step, :performing?
    end
    nested_action = Stepped::Action.last
    assert_predicate nested_action, :performing?
    assert_predicate nested_action, :outbound?
    assert_equal 100, @car.reload.mileage
    assert_nil @car.location

    assert_difference(
      "Stepped::Action.count" => 0,
      "Stepped::Step.count" => +1,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => -1
    ) do
      Stepped::Performance.outbound_complete @car, :drive
    end

    assert_predicate nested_action.reload, :succeeded?

    assert_equal 1, perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
    assert_predicate action.reload, :succeeded?
    assert_equal "London", @car.reload.location
  end
end
