require "test_helper"

class Stepped::ActionAsJobTest < Stepped::TestCase
  class TowJob < ActiveJob::Base
    queue_as :default

    def perform(action)
      car = action.actor
      location = action.arguments.first

      return retry_job if location == "retry"

      car.update!(location:)

      action.complete!
    end
  end

  setup do
    Temping.create "car" do
      with_columns do |t|
        t.integer :honks, default: 0
        t.string :location
      end

      stepped_action :tow, job: TowJob

      def honk
        increment! :honks
      end
    end

    @car = Car.create!
  end

  test "perform action defined as Job" do
    action = nil
    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Performance.count" => +1
    ) do
      assert_enqueued_with(job: TowJob) do
        action = Stepped::ActionJob.perform_now @car, :tow, "service"
      end
    end

    assert_predicate action, :performing?
    assert_predicate action.steps.first, :succeeded?

    assert_difference(
      "Stepped::Action.count" => 0,
      "Stepped::Step.count" => 0,
      "Stepped::Performance.count" => -1
    ) do
      perform_enqueued_jobs(only: TowJob)
    end

    assert_predicate action.reload, :succeeded?
    assert_predicate action, :outbound?
    assert_equal "service", @car.reload.location
    assert_equal 0, action.steps.first.pending_actions_count
  end

  test "job that retries itself" do
    action = nil
    assert_enqueued_with job: TowJob do
      action = Stepped::ActionJob.perform_now @car, :tow, "retry"
    end

    assert_enqueued_with job: TowJob do
      perform_enqueued_jobs(only: TowJob)
    end

    action.arguments = [ "Paris" ]
    action.save!

    assert_no_enqueued_jobs(only: TowJob) do
      perform_enqueued_jobs(only: TowJob)
    end

    assert_predicate action.reload, :succeeded?
  end

  test "prepending step to existing job action" do
    Car.prepend_stepped_action_step :tow do |step|
      honk
    end

    action = nil
    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +2,
      "Stepped::Performance.count" => +1
    ) do
      assert_enqueued_with(job: TowJob) do
        action = Stepped::ActionJob.perform_now @car, :tow, "service"
      end
    end

    assert_predicate action, :performing?
    assert_predicate action.steps.first, :succeeded?
    assert_equal 1, @car.honks

    assert_difference(
      "Stepped::Action.count" => 0,
      "Stepped::Step.count" => 0,
      "Stepped::Performance.count" => -1
    ) do
      perform_enqueued_jobs(only: TowJob)
    end

    assert_predicate action.reload, :succeeded?
    assert_equal 0, action.steps.first.pending_actions_count
    assert_equal 0, action.steps.second.pending_actions_count
    assert_equal 1, @car.reload.honks
    assert_equal "service", @car.location
  end
end
