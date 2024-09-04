require "test_helper"

class CommentTest < ActiveSupport::TestCase
  test "belongs to post" do
    comment = Comment.new(post: nil)
    comment.valid?
    assert_includes comment.errors[:post], "must exist"
  end

  test "belongs to user" do
    comment = Comment.new(user: nil)
    comment.valid?
    assert_includes comment.errors[:user], "must exist"
  end

  test "body cannot be nil" do
    comment = Comment.new(body: nil)
    comment.valid?
    assert_includes comment.errors[:body], "can't be blank"
  end

  test "body must be more than 5 characters" do
    comment = Comment.new(body: "1234")
    comment.valid?
    assert_includes comment.errors[:body], "is too short (minimum is 5 characters)"
  end
end
