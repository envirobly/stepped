require "test_helper"

class Stepped::StepExceptionsTest < Stepped::TestCase
  setup do
    Temping.create "car" do
      with_columns do |t|
        t.integer :honks, default: 0
      end

      def breakdown
        throw "oops"
      end

      def honk
        increment! :honks
      end
    end

    @car = Car.create!
  end

  test "exception in step body does not enqueue any actions part of that step" do
    Car.stepped_action :breakdown_wrapped do
      step do |step|
        step.do :honk
        breakdown
        step.do :honk
        honk
      end
    end

    handle_stepped_action_exceptions do
      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Step.count" => +1,
        "Stepped::Performance.count" => 0
      ) do
        assert_no_enqueued_jobs(only: Stepped::ActionJob) do
          assert Stepped::ActionJob.perform_now @car, :breakdown_wrapped
        end
      end

      step = Stepped::Step.last
      assert_predicate step, :failed?
      assert step.started_at
      assert step.completed_at
      assert_equal 0, step.pending_actions_count
      assert_equal 0, step.unsuccessful_actions_count

      parent_action = Stepped::Action.last
      assert_predicate parent_action, :failed?
      assert parent_action.started_at
      assert parent_action.completed_at

      assert_equal 0, @car.reload.honks
    end
  end
end
