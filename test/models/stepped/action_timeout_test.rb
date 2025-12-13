require "test_helper"

class Stepped::ActionTimeoutTest < Stepped::TestCase
  setup do
    Temping.create "car" do
      with_columns do |t|
        t.string :location
      end

      stepped_action :visit do
        step do |step, location|
          step.do :change_location, location
        end

        succeeded do
          throw "This should not be reached"
        end
      end

      stepped_action :change_location, outbound: true, timeout: 5.seconds do
        succeeded do
          throw "This should not be reached"
        end
      end

      def change_location(location)
        update!(location:)
      end
    end

    @car = Car.create!
  end

  test "action times out if not completed within the specified time" do
    start_at = Time.zone.local 2024, 12, 12
    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Performance.count" => +1
    ) do
      assert_enqueued_with(job: Stepped::TimeoutJob) do
        travel_to start_at do
          Stepped::ActionJob.perform_now @car, :change_location, "Copenhagen"
        end
      end
    end

    action = Stepped::Action.last
    assert_predicate action, :performing?
    assert_predicate action, :timeout?
    assert_equal 5.seconds, action.timeout
    assert_equal 5, action.timeout_seconds
    assert_equal start_at, action.started_at
    assert_equal "Copenhagen", @car.reload.location

    # TimeoutJob performs and action timed out
    timeout_at = start_at + 6.seconds
    assert_difference("Stepped::Performance.count" => -1) do
      travel_to timeout_at do
        assert_equal 1, perform_enqueued_jobs(only: Stepped::TimeoutJob)
      end
    end
    assert_predicate action.reload, :timed_out?
    assert_equal timeout_at, action.completed_at
  end

  test "timeout of nested action fails the parent step and parent action" do
    start_at = Time.zone.local 2024, 12, 12
    assert_difference(
      "Stepped::Action.count" => +2,
      "Stepped::Step.count" => +2,
      "Stepped::Performance.count" => +2
    ) do
      assert_enqueued_with(job: Stepped::TimeoutJob) do
        travel_to start_at do
          Stepped::ActionJob.perform_now @car, :visit, "Copenhagen"
          assert_equal 1, perform_enqueued_jobs(only: Stepped::ActionJob)
        end
      end
    end

    parent_action = Stepped::Action.last(2).first
    assert_predicate parent_action, :performing?
    assert_not_predicate parent_action, :timeout?
    assert_equal start_at, parent_action.started_at

    nested_action = Stepped::Action.last
    assert_predicate nested_action, :performing?
    assert_predicate nested_action, :timeout?
    assert_equal 5.seconds, nested_action.timeout
    assert_equal start_at, nested_action.started_at

    assert_equal "Copenhagen", @car.reload.location

    # TimeoutJob performs and action timed out
    timeout_at = start_at + 6.seconds
    assert_difference("Stepped::Performance.count" => -2) do
      travel_to timeout_at do
        assert_equal 1, perform_enqueued_jobs(only: Stepped::TimeoutJob)
      end
    end
    assert_predicate nested_action.reload, :timed_out?
    assert_equal timeout_at, nested_action.completed_at
    assert_predicate parent_action.reload, :failed?
    assert_equal timeout_at, parent_action.completed_at
  end
end
