require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:one)
  end

  test "should not find index" do
    get sessions_url
    assert_response :not_found
  end

  test "should get new" do
    get new_session_url
    assert_response :success
  end

  test "should create session" do
    assert_difference("Session.count") do
      post sessions_url, params: { session: { user: { screen_name: @session.user.screen_name, password: "secret" } } }
    end

    assert_redirected_to user_url(Session.last.user)
  end

  test "should not define show" do
    assert_raises NoMethodError do
      get session_url(@session)
    end
  end

  test "should not define edit" do
    assert_raises NoMethodError do
      get edit_session_url(@session)
    end
  end

  test "should not define update" do
    assert_raises NoMethodError do
      patch session_url(@session), params: { session: { ip_address: "NEW IP", user_agent: "NEW USER AGENT" } }
    end
  end

  test "should not define destroy" do
    assert_raises NoMethodError do
      delete session_url(@session)
    end
  end
end
