require "test_helper"

class Stepped::ActionSupersedingTest < Stepped::TestCase
  setup do
    Temping.create "car" do
      with_columns do |t|
        t.string :location
        t.integer :mileage, default: 0
      end

      def change_location(location)
        update!(location:)
      end

      def drive(mileage)
        self.mileage += mileage
        save!
      end
    end

    @car = Car.create!
  end

  test "superseeding of root actions" do
    Car.stepped_action :visit do
      step do |step, location|
        step.do :change_location, location
      end
    end

    Stepped::ActionJob.perform_now @car, :visit, "Bratislava"
    performance = Stepped::Performance.last
    first_action = Stepped::Action.last
    assert_equal "visit", first_action.name
    assert_equal performance, first_action.performance

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert_no_enqueued_jobs(only: Stepped::ActionJob) do
        Stepped::ActionJob.perform_now @car, :visit, "Paris"
      end
    end

    second_action = Stepped::Action.last
    assert_equal "visit", second_action.name
    assert_predicate second_action, :pending?
    assert_equal performance, second_action.performance

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert_no_enqueued_jobs(only: Stepped::ActionJob) do
        Stepped::ActionJob.perform_now @car, :visit, "Berlin"
      end
    end

    third_action = Stepped::Action.last
    assert_equal "visit", third_action.name
    assert_predicate third_action, :pending?
    assert_predicate second_action.reload, :superseded?
    assert_equal performance, third_action.performance
    assert_equal 3, performance.actions.count

    # Perform the first nested action of the first action
    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +2,
      "Stepped::Performance.count" => 0
    ) do
      assert_enqueued_with(job: Stepped::ActionJob) do
        assert_equal 1, perform_enqueued_jobs(only: Stepped::ActionJob)
      end
    end
    assert_predicate first_action.reload, :succeeded?
    assert_equal "Bratislava", @car.reload.location
    assert_predicate third_action.reload, :performing?
    assert_equal 2, performance.actions.count
    assert_equal "visit", performance.actions.first.name

    # Complete the last actions by completing the pending nested action
    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Performance.count" => -1
    ) do
      assert_no_enqueued_jobs(only: Stepped::ActionJob) do
        assert_equal 1, perform_enqueued_jobs(only: Stepped::ActionJob)
      end
      # puts Stepped::Action.last.attributes
    end
    assert_predicate third_action.reload, :succeeded?
    assert_equal "Berlin", @car.reload.location
  end

  test "superseeding of nested actions adds new action under the step where action was superseded" do
    Car.stepped_action :get_out_of_way do
      step do |step, mileage|
        step.do :drive, mileage
      end
    end

    Car.stepped_action :rush_hour_visit do
      step do |step, preceeding_car, location|
        step.on preceeding_car, :get_out_of_way, 1
      end

      step do |step, preceeding_car, location|
        step.do :change_location, location
      end
    end

    preceeding_car = Car.create!

    # Proceeding car starts performing get_out_of_way

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Performance.count" => +1
    ) do
      Stepped::ActionJob.perform_now preceeding_car, :get_out_of_way, 20
    end

    first_get_out_of_way_action = Stepped::Action.last
    assert_equal "get_out_of_way", first_get_out_of_way_action.name
    assert_predicate first_get_out_of_way_action, :performing?
    assert_equal 0, preceeding_car.reload.mileage

    first_get_out_of_way_performance = Stepped::Performance.last
    assert_equal 1, first_get_out_of_way_performance.actions.count
    assert_includes first_get_out_of_way_performance.actions, first_get_out_of_way_action

    # Now rush_hour_visit gets blocked by proceeding car's performing get_out_of_way

    assert_difference(
      "Stepped::Action.count" => +2,
      "Stepped::Step.count" => +1,
      "Stepped::Performance.count" => +1
    ) do
      perform_enqueued_jobs do
        Stepped::ActionJob.perform_now @car, :rush_hour_visit, preceeding_car, "Bratislava"
      end
    end

    rush_hour_visit_action = Stepped::Action.last(2).first
    assert_equal "rush_hour_visit", rush_hour_visit_action.name
    assert_predicate rush_hour_visit_action, :performing?
    assert_predicate first_get_out_of_way_action.reload, :performing?
    assert_equal 0, preceeding_car.reload.mileage
    second_get_out_of_way_action = Stepped::Action.last
    assert_equal "get_out_of_way", second_get_out_of_way_action.name
    assert_predicate second_get_out_of_way_action, :pending?
    assert_equal 2, first_get_out_of_way_performance.actions.count
    assert_equal first_get_out_of_way_action, first_get_out_of_way_performance.reload.action
    assert_includes first_get_out_of_way_performance.actions, second_get_out_of_way_action

    rush_hour_visit_first_step = Stepped::Step.last
    assert_predicate rush_hour_visit_first_step, :performing?

    # Proceeding car queues up another get_out_of_way action

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      Stepped::ActionJob.perform_now preceeding_car, :get_out_of_way, 300
    end

    assert_equal 0, preceeding_car.reload.mileage
    third_get_out_of_way_action = Stepped::Action.last
    assert_predicate third_get_out_of_way_action, :pending?
    assert_predicate second_get_out_of_way_action.reload, :superseded?
    assert_predicate first_get_out_of_way_action.reload, :performing?
    assert_equal 3, first_get_out_of_way_performance.actions.count
    assert_equal 1, first_get_out_of_way_performance.actions.pending.count
    assert_includes first_get_out_of_way_performance.actions, third_get_out_of_way_action

    assert_equal 2, rush_hour_visit_first_step.actions.count
    assert_equal 1, rush_hour_visit_first_step.pending_actions_count
    assert_equal 1, rush_hour_visit_first_step.actions.superseded.count
    assert_equal second_get_out_of_way_action, rush_hour_visit_first_step.actions.superseded.sole
    assert_equal 1, rush_hour_visit_first_step.actions.pending.count
    assert_equal third_get_out_of_way_action, rush_hour_visit_first_step.actions.pending.sole

    # Finish everything

    assert_difference(
      "Stepped::Action.count" => +3,
      "Stepped::Step.count" => +5,
      "Stepped::Performance.count" => -2
    ) do
      assert_equal 3, perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
    end

    assert_equal %w[ drive drive change_location ], Stepped::Action.last(3).pluck(:name)

    Stepped::Action.last(3).each do |action|
      assert_predicate action, :succeeded?
      assert_nil action.performance
    end

    assert_predicate rush_hour_visit_action.reload, :succeeded?
    assert_nil rush_hour_visit_action.performance
    assert_equal 320, preceeding_car.reload.mileage
  end

  test "performing actions with same checksum and concurrency_key but different checksum_key" do
    Car.stepped_action :tiny_drive do
      concurrency_key { "Car/drive" }
      checksum { 1 }
      checksum_key { "tiny_drive" }

      step do |step|
        step.do :drive, 1
      end
    end

    Car.stepped_action :short_drive do
      concurrency_key { "Car/drive" }
      checksum { 1 }
      checksum_key { "short_drive" }

      step do |step|
        step.do :drive, 10
      end
    end

    first_action = Stepped::ActionJob.perform_now @car, :tiny_drive
    assert_predicate first_action, :performing?

    performance = Stepped::Performance.last
    assert_equal "Car/drive", performance.concurrency_key

    # Queue up short_drive
    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert_predicate Stepped::ActionJob.perform_now(@car, :short_drive), :pending?
    end
    second_action = Stepped::Action.last
    assert_predicate second_action, :pending?
    assert_equal 2, performance.actions.count

    # Another tiny_drive drive is achieved by performing tiny_drive, so nothing gets created
    assert_difference(
      "Stepped::Action.count" => 0,
      "Stepped::Step.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert_equal first_action, Stepped::ActionJob.perform_now(@car, :tiny_drive)
    end

    # Complete everything
    assert_difference(
      "Stepped::Action.count" => +2,
      "Stepped::Step.count" => +3,
      "Stepped::Performance.count" => -1
    ) do
      perform_stepped_actions
    end
    assert_predicate second_action.reload, :succeeded?
  end
end
