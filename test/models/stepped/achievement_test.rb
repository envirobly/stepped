require "test_helper"

class Stepped::AchievementTest < Stepped::TestCase
  test "checksum_key must be unique" do
    assert_difference "Stepped::Achievement.count" => +1 do
      Stepped::Achievement.create!(checksum_key: "one", checksum: "1")
    end
    assert_raises ActiveRecord::RecordNotUnique do
      Stepped::Achievement.create!(checksum_key: "one", checksum: "2")
    end
  end
end
