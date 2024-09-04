require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "belongs to user" do
    post = Post.new(user: nil)
    post.valid?
    assert_includes post.errors[:user], "must exist"
  end

  test "title cannot be nil" do
    post = Post.new(title: nil)
    post.valid?
    assert_includes post.errors[:title], "can't be blank"
  end

  test "title must be unique" do
    one = posts(:one)
    post = Post.new(title: one.title)
    post.valid?
    assert_includes post.errors[:title], "has already been taken"
  end

  test "title must be more than 5 characters" do
    post = Post.new(title: "1234")
    post.valid?
    assert_includes post.errors[:title], "is too short (minimum is 5 characters)"
  end
end
