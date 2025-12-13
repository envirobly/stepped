require "test_helper"

class SampleTest < ActiveSupport::TestCase
  test "inherits from ApplicationRecord" do
    assert_equal ApplicationRecord, Sample.superclass
  end

  test "stepped_action class method has been included" do
    assert Sample.respond_to?(:stepped_action)
  end
end
