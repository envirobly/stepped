require "test_helper"

class Stepped::PerformanceTest < Stepped::TestCase
  setup do
    Temping.create "account" do
      with_columns do |t|
        t.string :name
      end

      stepped_action :fly

      def fly; end
    end

    @account = Account.create!(name: "Acme Org")
  end

  test "only one action performance can exist at a time" do
    action = create_action
    assert_difference "Stepped::Performance.count" => +1 do
      Stepped::Performance.create!(action:)
    end
    assert_raises ActiveRecord::RecordNotUnique do
      Stepped::Performance.create!(action:)
    end
  end

  test "must have nil or unique concurrency key" do
    assert_difference "Stepped::Performance.count" => +3 do
      Stepped::Performance.create!(action: create_action, concurrency_key: nil)
      Stepped::Performance.create!(action: create_action, concurrency_key: nil)
      Stepped::Performance.create!(action: create_action, concurrency_key: "a")
    end
    assert_raises ActiveRecord::RecordNotUnique do
      Stepped::Performance.create!(action: create_action, concurrency_key: "a")
    end
  end

  def create_action
    actor = @account
    Stepped::Action.new(actor:, name: "fly").tap(&:apply_definition).tap(&:save!)
  end
end
