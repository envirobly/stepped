require "test_helper"

class Stepped::ActionConcurrencyKeyTest < Stepped::TestCase
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

  test "concurrency_key defined as string" do
    Car.stepped_action :drive_one_way_street do
      concurrency_key do
        "just-a-string"
      end
    end

    action = Stepped::Action.new(actor: @car, name: :drive_one_way_street)
    action.apply_definition
    assert_equal "just-a-string", action.concurrency_key
  end

  test "concurrency_key defined as blank means to use default (tenancy_key)" do
    [ nil, "", [] ].each do |value|
      Car.stepped_action :drive_one_way_street do
        concurrency_key { value }
      end

      action = Stepped::Action.new(actor: @car, name: :drive_one_way_street)
      action.apply_definition
      assert_equal action.send(:tenancy_key), action.concurrency_key
    end
  end

  test "actions on different actors with custom concurrency keys that matches ensures they queue up" do
    Car.stepped_action :drive_one_way_street do
      concurrency_key do
        [ "Car", "drive_one_way_street" ]
      end

      step do |step, mileage|
        step.do :drive, mileage
      end
    end

    first_car = @car
    second_car = Car.create!

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Performance.count" => +1
    ) do
      assert Stepped::ActionJob.perform_now first_car, :drive_one_way_street, 1
    end

    performance = Stepped::Performance.last
    first_car_action = Stepped::Action.last
    assert_equal "Car/drive_one_way_street", first_car_action.concurrency_key
    assert_equal performance, first_car_action.performance
    assert_predicate first_car_action, :performing?

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert_predicate Stepped::ActionJob.perform_now(second_car, :drive_one_way_street, 2), :pending?
    end

    second_car_action = Stepped::Action.last
    assert_equal "Car/drive_one_way_street", second_car_action.concurrency_key
    assert_equal performance, second_car_action.performance
    assert_predicate second_car_action, :pending?

    # Finish first action
    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +2,
      "Stepped::Performance.count" => 0
    ) do
      assert_equal 1, perform_enqueued_jobs(only: Stepped::ActionJob)
    end

    assert_predicate first_car_action.reload, :succeeded?
    assert_equal 1, first_car.reload.mileage
    assert_predicate second_car_action.reload, :performing?

    # Finish second action
    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Performance.count" => -1
    ) do
      assert_equal 1, perform_enqueued_jobs(only: Stepped::ActionJob)
    end
    assert_predicate second_car_action.reload, :succeeded?
    assert_equal 2, second_car.reload.mileage
  end

  test "cancelling queued action attached to performance while the first one is performing" do
    Car.stepped_action :drive, outbound: true

    assert_difference "Stepped::Performance.count" => +1 do
      assert_predicate Stepped::ActionJob.perform_now(@car, :drive, 1), :performing?
      assert_predicate Stepped::ActionJob.perform_now(@car, :drive, 2), :pending?
    end

    performance = Stepped::Performance.last
    assert_equal 2, performance.actions.size

    first_action = performance.actions.first
    assert_predicate first_action, :performing?

    second_action = performance.actions.second
    assert_predicate second_action, :pending?

    assert_no_difference "Stepped::Performance.count" do
      second_action.complete!(:cancelled)
    end

    assert_predicate second_action.reload, :cancelled?
    assert_nil second_action.performance
    assert_predicate first_action.reload, :performing?
    assert_equal performance, first_action.performance
    assert_equal 1, performance.actions.count

    assert_difference "Stepped::Performance.count" => -1 do
      Stepped::Performance.outbound_complete(@car, :drive)
    end

    assert_predicate first_action.reload, :succeeded?
  end

  test "same concurrency_key does not complete action that doesn't match actor or name" do
    Car.define_method :recycle do; end
    Car.define_method :paint do; end
    Car.stepped_action :recycle, outbound: true do
      concurrency_key { "Car/maintenance" }
    end
    Car.stepped_action :paint, outbound: true do
      concurrency_key { "Car/maintenance" }
    end

    recycle_action = Stepped::ActionJob.perform_now @car, :recycle
    assert_predicate recycle_action, :performing?
    assert_equal "recycle", recycle_action.name
    assert_predicate Stepped::ActionJob.perform_now(@car, :paint), :pending?
    paint_action = Stepped::Action.last
    assert_predicate paint_action, :pending?
    assert_equal "paint", paint_action.name

    # Attempt to complete the action that is not actually performing, but has the same concurrency_key
    assert_no_difference "Stepped::Performance.count" do
      assert_not Stepped::Performance.outbound_complete(@car, :paint)
    end
    assert_predicate recycle_action.reload, :performing?
    assert_predicate paint_action.reload, :pending?
  end

  test "descendent action can't have the same concurrency_key as parent" do
    Car.stepped_action :recycle do
      concurrency_key { "Car/maintenance" }

      step do |step|
        step.do :prepare_recycle
      end
    end
    Car.stepped_action :prepare_recycle do
      step do |step|
        step.do :drive, 1
      end
    end
    Car.stepped_action :drive do
      concurrency_key { "Car/maintenance" }
    end

    handle_stepped_action_exceptions(only: Stepped::Action::Deadlock) do
      recycle_action = nil
      assert_difference "Stepped::Action.count" => +2 do
        recycle_action = Stepped::ActionJob.perform_now @car, :recycle
        perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
      end
      assert_predicate recycle_action.reload, :failed?
    end
  end

  test "concurrency_key can use action arguments" do
    Car.stepped_action :fun do
      concurrency_key do |arg1, arg2|
        "#{arg1}-#{arg2}"
      end

      step { }
    end

    action = Stepped::ActionJob.perform_now(@car, :fun, "foo", "bar")
    assert_equal "foo-bar", action.concurrency_key
  end
end
