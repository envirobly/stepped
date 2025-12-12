# frozen_string_literal: true

require "test_helper"

class SteppedActiveRecordTest < ActiveSupport::TestCase
  test "ActiveRecord::Base gets stepped_test helper" do
    assert ActiveRecord::Base.method_defined?(:stepped_test)
    assert_equal "stepped here", ActiveRecord::Base.allocate.stepped_test
  end
end
