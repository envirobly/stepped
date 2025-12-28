require "test_helper"

class SteppedCarTest < Stepped::TestCase
  setup do
    Temping.create("Stepped::Car") do
      with_columns do |t|
        t.string :make
        t.string :model
      end
    end
  end

  test "persists a namespaced car created within the test" do
    car = Stepped::Car.create!(make: "Volvo", model: "XC40")

    assert_predicate car, :persisted?
    assert_equal %w[Volvo XC40], [ car.make, car.model ]
  end
end
