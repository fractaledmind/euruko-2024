require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "should not find index" do
    get users_url
    assert_response :not_found
  end

  test "should get new" do
    get new_user_url
    assert_response :success
  end

  test "should create user" do
    assert_difference("User.count") do
      post users_url, params: { user: { screen_name: "new_user", password: "secret", password_confirmation: "secret" } }
    end

    assert_redirected_to user_url(User.last)
  end

  test "should show user" do
    get user_url(@user)
    assert_response :success
  end

  test "should not define edit" do
    assert_raises NoMethodError do
      get edit_user_url(@user)
    end
  end

  test "should not find update" do
    patch user_url(@user), params: { user: { about: @user.about, last_seen_at: @user.last_seen_at, password: "secret", password_confirmation: "secret", screen_name: @user.screen_name } }
    assert_response :not_found
  end

  test "should not find destroy" do
    assert_difference("User.count", 0) do
      delete user_url(@user)
    end

    assert_response :not_found
  end
end
