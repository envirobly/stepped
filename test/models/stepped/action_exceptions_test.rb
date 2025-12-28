require "test_helper"

class Stepped::ActionExceptionsTest < Stepped::TestCase
  setup do
    Temping.create "car" do
      with_columns do |t|
        t.integer :honks, default: 0
      end

      def breakdown
        raise StandardError
      end

      def honk
        increment! :honks
      end
    end

    @car = Car.create!
  end

  test "exception in direct method call with error raising disabled" do
    handle_stepped_action_exceptions do
      action =
        assert_difference(
          "Stepped::Action.count" => +1,
          "Stepped::Performance.count" => 0,
          "Stepped::Step.count" => +1
        ) do
          Stepped::ActionJob.perform_now @car, :breakdown
        end
      assert_predicate action, :failed?
      assert action.started_at
      assert action.completed_at
      assert_equal 0, @car.reload.honks
    end
  end

  test "exception in direct method call with definition with failed callback with error raising disabled" do
    Car.stepped_action :breakdown do
      failed do
        honk
      end
    end

    handle_stepped_action_exceptions do
      Stepped::ActionJob.perform_now @car, :breakdown
      action = Stepped::Action.last
      assert_predicate action, :failed?
      assert_equal 1, @car.reload.honks
    end
  end

  test "exception in a nested action with error raising disabled and failed callback" do
    Car.stepped_action :breakdown_wrapped do
      step do |step|
        step.do :breakdown
      end

      failed do
        honk
      end
    end

    handle_stepped_action_exceptions do
      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Performance.count" => +1,
        "Stepped::Step.count" => +1
      ) do
        assert_enqueued_with(job: Stepped::ActionJob) do
          Stepped::ActionJob.perform_now @car, :breakdown_wrapped
        end
      end

      parent_action = Stepped::Action.last

      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Performance.count" => -1,
        "Stepped::Step.count" => +1
      ) do
        assert_equal 1, perform_enqueued_jobs(only: Stepped::ActionJob)
      end

      action = Stepped::Action.last
      assert_predicate action, :failed?
      assert action.started_at
      assert action.completed_at

      step = Stepped::Step.last
      assert_predicate step, :failed?
      assert action.started_at
      assert action.completed_at

      assert_predicate parent_action.reload, :failed?
      assert parent_action.started_at
      assert parent_action.completed_at

      assert_equal 1, @car.reload.honks
    end
  end

  test "exception in failed callback" do
    Car.stepped_action :breakdown_wrapped do
      step do |step|
        step.do :breakdown
      end

      failed do
        honk
        raise StandardError
      end
    end

    handle_stepped_action_exceptions do
      Stepped::ActionJob.perform_now @car, :breakdown_wrapped
      parent_action = Stepped::Action.last
      assert_equal 1, perform_enqueued_jobs(only: Stepped::ActionJob)

      action = Stepped::Action.last
      assert_predicate action, :failed?
      step = Stepped::Step.last
      assert_predicate step, :failed?
      assert_predicate parent_action.reload, :failed?
      assert_equal 1, @car.reload.honks
    end
  end

  test "exception in succeeded callback doesn't change action status and doesn't generate Achievement" do
    Car.stepped_action :honk do
      checksum { "a" }

      succeeded do
        raise StandardError
      end
    end

    handle_stepped_action_exceptions do
      action =
        assert_no_difference "Stepped::Achievement.count" do
          Stepped::ActionJob.perform_now @car, :honk
        end
      assert_predicate action, :succeeded?
      assert_not_predicate action, :succeeded_including_callbacks?
      assert_equal 1, @car.reload.honks
      assert_nil action.after_callbacks_succeeded_count
      assert_equal 1, action.after_callbacks_failed_count
    end
  end

  test "exception in direct method call with error raising enabled" do
    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Performance.count" => +1,
      "Stepped::Step.count" => +1
    ) do
      assert_raises StandardError do
        Stepped::ActionJob.perform_now @car, :breakdown
      end
    end

    action = Stepped::Action.last
    assert_predicate action, :performing?
    assert action.started_at
    assert_nil action.completed_at
  end

  test "action that fails without checksum deletes its Achievement record" do
    handle_stepped_action_exceptions do
      achievement = Stepped::Achievement.create!(
        checksum_key: "Car/#{@car.id}/breakdown",
        checksum: Stepped.checksum("something")
      )
      Car.stepped_action :breakdown do
        step do
          throw "fail"
        end
      end
      action =
        assert_difference(
          "Stepped::Action.count" => +1,
          "Stepped::Step.count" => +1,
          "Stepped::Achievement.count" => -1,
          "Stepped::Performance.count" => 0
        ) do
          Stepped::ActionJob.perform_now @car, :breakdown
        end
      assert_predicate action, :failed?
      assert_raises ActiveRecord::RecordNotFound do
        achievement.reload
      end
    end
  end

  test "before block exception is captured and halts action creation" do
    handle_stepped_action_exceptions do
      Car.stepped_action :breakdown do
        before do
          throw "fail"
        end
      end
      assert_difference(
        "Stepped::Action.count" => 0,
        "Stepped::Step.count" => 0,
        "Stepped::Achievement.count" => 0,
        "Stepped::Performance.count" => 0
      ) do
        assert_predicate Stepped::ActionJob.perform_now(@car, :breakdown), :failed?
      end
    end
  end

  test "before block exception in nested action fails the parent action" do
    handle_stepped_action_exceptions do
      Car.stepped_action :wrap_breakdown do
        step do |step|
          step.do :breakdown
        end
      end
      Car.stepped_action :breakdown do
        before do
          throw "fail"
        end
      end
      action = nil
      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Step.count" => +1,
        "Stepped::Achievement.count" => 0,
        "Stepped::Performance.count" => 0
      ) do
        action = Stepped::ActionJob.perform_now @car, :wrap_breakdown
        perform_enqueued_jobs(only: Stepped::ActionJob)
      end
      assert_predicate action.reload, :failed?
      assert_predicate action.steps.first, :failed?
    end
  end
end
