require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "screen_name cannot be nil" do
    user = User.new(screen_name: nil)
    user.valid?
    assert_includes user.errors[:screen_name], "can't be blank"
  end

  test "screen_name must be unique" do
    one = users(:one)
    user = User.new(screen_name: one.screen_name)
    user.valid?
    assert_includes user.errors[:screen_name], "has already been taken"
  end
end
