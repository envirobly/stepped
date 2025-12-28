require "test_helper"

class Stepped::RegistryTest < Stepped::TestCase
  STEP_ONE = proc { }
  STEP_TWO = proc { }
  AFTER_CALLBACK = proc { }
  STEP = proc { }

  class Car
    include Stepped::Actionable

    stepped_action :drive do
      step &STEP_ONE
      step &STEP_TWO
      after &AFTER_CALLBACK
    end
  end

  class FlyJob; end
  class FlyingCar < Car
    stepped_action :fly, job: FlyJob
  end

  class DifferentlyDrivingCar < Car
    stepped_action :drive do
      step &STEP
    end
  end

  test "job_classes lists all job classes that have been used in definitions" do
    assert_includes Stepped::Registry.job_classes, FlyJob
  end

  test "find when action is not defined for a class" do
    assert_nil Stepped::Registry.find(Car, :fly)
  end

  [ :drive, "drive" ].each do |action_name|
    test "find when action is defined when action name is a #{action_name.class.name}" do
      definition = Stepped::Registry.find(Car, action_name)
      assert_kind_of Stepped::Definition, definition
      assert_equal "drive", definition.action_name
      assert_equal Car, definition.actor_class
      assert_equal 2, definition.steps.size
      assert_equal STEP_ONE, definition.steps.first
      assert_equal STEP_TWO, definition.steps.second
      definition.steps.each do |step_definition|
        assert_kind_of Proc, step_definition
      end
      assert_equal 1, definition.after_callbacks.size
      assert_equal AFTER_CALLBACK, definition.after_callbacks.first[:block]
    end
  end

  test "parent does not get childs definitions" do
    assert_nil Stepped::Registry.find(Car, :fly)
  end

  test "inheriting and action from parent" do
    definition = Stepped::Registry.find(FlyingCar, :drive)
    assert_equal Car, definition.actor_class
    assert_equal definition, Stepped::Registry.find(Car, :drive)
  end

  test "override of inherited definition" do
    definition = Stepped::Registry.find DifferentlyDrivingCar, :drive
    assert_equal 1, definition.steps.size
    assert_equal STEP, definition.steps.first
    assert_not_equal definition, Stepped::Registry.find(Car, :drive)
  end

  test "adding after callbacks to child doesn't modify parent action" do
    one = proc { }
    two = proc { }
    FlyingCar.after_stepped_action :drive, &one
    FlyingCar.after_stepped_action :drive, &two

    parent_definition = Stepped::Registry.find(Car, :drive)
    assert_equal 1, parent_definition.after_callbacks.size
    assert_equal AFTER_CALLBACK, parent_definition.after_callbacks.first[:block]

    definition = Stepped::Registry.find(FlyingCar, :drive)
    assert_not_equal definition, parent_definition
    assert_equal 3, definition.after_callbacks.size
    assert_equal AFTER_CALLBACK, definition.after_callbacks.first[:block]
    assert_equal one, definition.after_callbacks.second[:block]
    assert_equal two, definition.after_callbacks.third[:block]
  ensure
    # TODO: This is a weakness of the current registry global state in tests,
    # where definitions in one test, affect the rest of the suite.
    Stepped::Registry.definitions.delete "Stepped::RegistryTest::FlyingCar/#{FlyingCar.object_id}"
  end
end
