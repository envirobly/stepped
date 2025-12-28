require "test_helper"

class Stepped::ActionChecksumsTest < Stepped::TestCase
  setup do
    Temping.create "car" do
      with_columns do |t|
        t.string :location
        t.integer :mileage, default: 0
      end

      stepped_action :visit do
        checksum do |location|
          location
        end

        step do |step, location|
          step.do :change_location, location
        end
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

  test "module checksum" do
    assert_equal "b7a56873cd771f2c446d369b649430b65a756ba278ff97ec81bb6f55b2e73569", Stepped.checksum(25)
    assert_equal "0473ef2dc0d324ab659d3580c1134e9d812035905c4781fdd6d529b0c6860e13", Stepped.checksum([ "a", "b" ])
  end

  test "module checksum with nil input is nil" do
    assert_nil Stepped.checksum(nil)
  end

  test "default checksum_key" do
    action = Stepped::Action.new(actor: @car, name: :visit)
    action.apply_definition
    assert_equal "Car/#{@car.id}/visit", action.checksum_key
  end

  test "custom checksum_key as string" do
    Car.stepped_action :visit do
      checksum_key do
        "custom"
      end
    end
    action = Stepped::Action.new(actor: @car, name: :visit)
    action.apply_definition
    assert_equal "custom", action.checksum_key
  end

  test "custom checksum_key as array" do
    Car.stepped_action :visit do
      checksum_key do
        [ "Car", "visit" ]
      end
    end
    action = Stepped::Action.new(actor: @car, name: :visit)
    action.apply_definition
    assert_equal "Car/visit", action.checksum_key
  end

  test "performing action is reused if checksum matches" do
    first_action =
      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Step.count" => +1,
        "Stepped::Achievement.count" => 0,
        "Stepped::Performance.count" => +1
      ) do
        Stepped::ActionJob.perform_now @car, :visit, "London"
      end

    assert_kind_of Stepped::Action, first_action
    assert_predicate first_action, :performing?
    assert_equal Stepped.checksum("London"), first_action.checksum
    assert_equal "Car/#{@car.id}/visit", first_action.checksum_key

    # No root action is created if performing the same checksum already

    assert_difference(
      "Stepped::Action.count" => 0,
      "Stepped::Step.count" => 0,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert_equal first_action, Stepped::ActionJob.perform_now(@car, :visit, "London")
    end

    # Finish everything

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Achievement.count" => +1,
      "Stepped::Performance.count" => -1
    ) do
      assert_equal 1, perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
    end

    assert_predicate first_action.reload, :succeeded?
    assert_equal "London", @car.reload.location

    achievement = Stepped::Achievement.last
    assert_equal "Car/#{@car.id}/visit", achievement.checksum_key
    assert_equal Stepped.checksum("London"), achievement.checksum

    # Try again with the same checksum, no action should be created as achievement is on that checksum

    assert_difference(
      "Stepped::Action.count" => 0,
      "Stepped::Step.count" => 0,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert_predicate Stepped::ActionJob.perform_now(@car, :visit, "London"), :succeeded?
    end

    # Try again with different checksum, action is created...

    assert_difference(
      "Stepped::Action.count" => +2,
      "Stepped::Step.count" => +2,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert Stepped::ActionJob.perform_now(@car, :visit, "Berlin")

      # After action starts current achievement is destroyed
      assert_raises ActiveRecord::RecordNotFound do
        achievement.reload
      end

      assert_equal 1, perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
    end

    # ...and after finishing it, Achievement is updated to new checksum
    assert_equal "Berlin", @car.reload.location
    achievement = Stepped::Achievement.last
    assert_equal "Car/#{@car.id}/visit", achievement.checksum_key
    assert_equal Stepped.checksum("Berlin"), achievement.checksum
  end

  test "completing action with nil checksum deletes Achievement if it exists for this action and achievement" do
    achievement = Stepped::Achievement.create!(
      checksum_key: "Car/#{@car.id}/drive",
      checksum: Stepped.checksum("something")
    )
    action =
      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Step.count" => +1,
        "Stepped::Achievement.count" => -1,
        "Stepped::Performance.count" => 0
      ) do
        Stepped::ActionJob.perform_now @car, :drive, 1
      end
    assert_nil action.checksum
    assert_equal 1, @car.reload.mileage
    assert_raises ActiveRecord::RecordNotFound do
      achievement.reload
    end
  end

  test "parent step of nested action matching and already performing checksum receives the matching action" do
    Car.stepped_action :trip do
      step do |step|
        step.do :visit, "Paris"
      end

      step do |step|
        step.do :visit, "Amsterdam"
      end
    end

    # Start the action that will later be reused within another action's step due to matching checksum
    Stepped::ActionJob.perform_now @car, :visit, "Paris"
    first_visit_action = Stepped::Action.last
    assert_predicate first_visit_action, :performing?

    trip_action =
      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Step.count" => +1,
        "Stepped::Achievement.count" => 0,
        "Stepped::Performance.count" => +1
      ) do
        perform_enqueued_jobs(only: Stepped::ActionJob) do
          Stepped::ActionJob.perform_now @car, :trip
        end
      end

    assert_predicate trip_action, :performing?
    assert_predicate first_visit_action.reload, :performing?

    step = Stepped::Step.last
    assert_predicate step, :performing?
    assert_equal 1, step.actions.count
    assert_includes step.actions, first_visit_action, "Already performing action was shared with this step"

    # Finish everything
    assert_difference(
      "Stepped::Action.count" => +3,
      "Stepped::Step.count" => +4,
      "Stepped::Achievement.count" => +1,
      "Stepped::Performance.count" => -2
    ) do
      assert_equal 3, perform_enqueued_jobs_recursively(only: Stepped::ActionJob)
    end

    assert_predicate trip_action.reload, :succeeded?
    assert_predicate first_visit_action.reload, :succeeded?

    achievement = Stepped::Achievement.last
    assert_equal "Car/#{@car.id}/visit", achievement.checksum_key
    assert_equal Stepped.checksum("Amsterdam"), achievement.checksum
  end

  test "reuse of completed action by checksum as nested action completes the step" do
    @car.update! location: "Paris"
    achievement = Stepped::Achievement.create!(
      checksum_key: "Car/#{@car.id}/visit",
      checksum: Stepped.checksum("Paris")
    )

    Car.stepped_action :tour do
      step do |step|
        step.do :visit, "Paris"
      end
    end

    action =
      assert_difference(
        "Stepped::Action.count" => +1,
        "Stepped::Step.count" => +1,
        "Stepped::Achievement.count" => 0,
        "Stepped::Performance.count" => +1
      ) do
        Stepped::ActionJob.perform_now @car, :tour
      end

    assert_predicate action, :performing?
    step = Stepped::Step.last
    assert_predicate step, :performing?
    assert_equal 1, step.pending_actions_count
    assert_equal 0, step.unsuccessful_actions_count

    assert_difference(
      "Stepped::Action.count" => 0,
      "Stepped::Step.count" => 0,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => -1
    ) do
      assert_equal 1, perform_enqueued_jobs(only: Stepped::ActionJob)
    end

    assert_predicate action.reload, :succeeded?
    assert_predicate step.reload, :succeeded?
    assert_equal 0, step.pending_actions_count
    assert_equal 0, step.unsuccessful_actions_count

    assert_equal Stepped.checksum("Paris"), achievement.reload.checksum
  end

  test "action reuse based on custom checksum_key" do
    Car.stepped_action :drive do
      checksum_key do
        [ "Car", "drive" ]
      end

      checksum do |mileage|
        mileage
      end
    end

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Achievement.count" => +1,
      "Stepped::Performance.count" => 0
    ) do
      assert Stepped::ActionJob.perform_now(@car, :drive, 1)
    end

    achievement = Stepped::Achievement.last
    assert_equal "Car/drive", achievement.checksum_key
    assert_equal Stepped.checksum(1), achievement.checksum
    assert_equal 1, @car.reload.mileage

    # Reuse based on checksum and scope from different models

    assert_difference(
      "Stepped::Action.count" => 0,
      "Stepped::Step.count" => 0,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert_predicate Stepped::ActionJob.perform_now(@car, :drive, 1), :succeeded?
    end

    assert_difference(
      "Stepped::Action.count" => 0,
      "Stepped::Step.count" => 0,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert_predicate Stepped::ActionJob.perform_now(Car.create!, :drive, 1), :succeeded?
    end

    # Checksum changed

    assert_difference(
      "Stepped::Action.count" => +1,
      "Stepped::Step.count" => +1,
      "Stepped::Achievement.count" => 0,
      "Stepped::Performance.count" => 0
    ) do
      assert Stepped::ActionJob.perform_now(@car, :drive, 2)
    end

    assert_raises ActiveRecord::RecordNotFound do
      achievement.reload
    end

    achievement = Stepped::Achievement.last
    assert_equal "Car/drive", achievement.checksum_key
    assert_equal Stepped.checksum(2), achievement.checksum
    assert_equal 3, @car.reload.mileage
  end
end
