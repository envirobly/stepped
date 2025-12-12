# frozen_string_literal: true

require "test_helper"
require_relative "../app/models/stepped/sample"

class SteppedSampleTest < ActiveSupport::TestCase
  setup do
    ActiveRecord::Schema.define do
      create_table :stepped_samples, force: true do |t|
        t.string :name
      end
    end
  end

  test "sample model responds to stepped_test helper" do
    sample = Stepped::Sample.create!(name: "example")

    assert_equal "stepped here", sample.stepped_test
  end

  test "greeting uses persisted name" do
    sample = Stepped::Sample.create!(name: "example")

    assert_equal "Hello, example", sample.greeting
  end
end
