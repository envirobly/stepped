require "test_helper"

class Stepped::ActionPrependStepTestTest < Stepped::TestCase
  setup do
    Temping.create "car" do
      with_columns do |t|
        t.integer :honks, default: 0
        t.integer :oinks, default: 0
        t.integer :boinks, default: 0
        t.integer :befores, default: 0
      end

      stepped_action :interact do
        before do
          increment! :befores
        end

        checksum { 1 }

        step do |step|
          step.do :honk
        end
      end

      prepend_stepped_action_step :interact do |step|
        step.do :oink
      end

      stepped_action :boink do
        step do |step|
          step.do :interact
        end

        step do
          increment! :boinks
        end
      end

      def honk
        increment! :honks
      end

      def oink
        increment! :oinks
      end
    end

    @car = Car.create!
  end

  test "step prepended after action definition" do
    action =
      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Step.count" => +1,
        "Stepped::Performance.count" => +1
      ) do
        @car.interact_now
      end
    assert_predicate action, :performing?
    assert_equal "interact", action.name
    assert_equal Stepped.checksum(1), action.checksum
    assert_equal "Car/#{@car.id}/interact", action.concurrency_key
    assert_equal "Car/#{@car.id}/interact", action.checksum_key
    assert_equal 0, @car.reload.oinks
    assert_equal 0, @car.honks
    assert_equal 1, @car.befores

    step = Stepped::Step.last
    assert_predicate step, :performing?

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +2,
      "Stepped::Performance.count" => 0,
      "Stepped::Achievement.count" => 0
    ) do
      perform_enqueued_jobs(only: Stepped::ActionJob)
    end

    assert_predicate action.reload, :performing?
    assert_equal 1, @car.reload.oinks
    assert_equal 0, @car.honks
    assert_equal 1, @car.befores

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Performance.count" => -1,
      "Stepped::Achievement.count" => +1
    ) do
      perform_enqueued_jobs(only: Stepped::ActionJob)
    end

    assert_predicate action.reload, :succeeded?
    assert_equal Stepped.checksum(1), action.checksum
    assert_equal Stepped::Achievement.last.checksum, action.checksum

    assert_equal 1, @car.reload.oinks
    assert_equal 1, @car.honks
    assert_equal 1, @car.befores
  end

  test "exception in dependencies block fails the action" do
    Car.stepped_action :born_to_fail do
      step do
        throw "this should not be reached"
      end
    end
    Car.prepend_stepped_action_step :born_to_fail do
      raise StandardError
    end

    handle_stepped_action_exceptions do
      action =
        assert_difference "Stepped::Action.count" => +1 do
          @car.born_to_fail_now
        end
      assert_equal "born_to_fail", action.name
      assert_predicate action, :failed?
    end
  end
end
