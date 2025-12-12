# frozen_string_literal: true

require "test_helper"

class SteppedActiveRecordTest < ActiveSupport::TestCase
  setup do
    Temping.create(:stepped_widget) do
      with_columns do |t|
        t.string :name
      end
    end
  end

  test "Temping model gets stepped_test helper" do
    widget = SteppedWidget.create!(name: "widget")

    assert_respond_to widget, :stepped_test
    assert_equal "stepped here", widget.stepped_test
  end
end
