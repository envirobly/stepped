require "test_helper"

class SteppedTest < Stepped::TestCase
  test "it has a version number" do
    assert Stepped::VERSION
  end

  test "engine model is included" do
    assert_kind_of Class, Stepped::Action
  end
end
