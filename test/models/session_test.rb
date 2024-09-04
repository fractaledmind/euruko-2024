require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "belongs to user" do
    session = Session.new(user: nil)
    session.valid?
    assert_includes session.errors[:user], "must exist"
  end
end
