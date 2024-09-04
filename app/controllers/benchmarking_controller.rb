class BenchmarkingController < ApplicationController
  skip_before_action :verify_authenticity_token
  allow_unauthenticated_access
  before_action :sign_in_random_user

  def post_create
    @post = Post.create!(user: @user, title: "Post #{request.uuid}", content: format(request:))
    render "posts/show", status: :ok
  end

  def comment_create
    @post = Post.where("id >= ?", rand(Post.minimum(:id)..Post.maximum(:id))).limit(1).first
    comment = Comment.create!(user: @user, post: post, body: "Comment #{request.uuid}")
    render "posts/show", status: :ok
  end

  def post_destroy
    post = Post.where("id >= ?", rand(Post.minimum(:id)..Post.maximum(:id))).limit(1).first
    post.destroy!
    posts_index
  end

  def comment_destroy
    comment = Comment.where("id >= ?", rand(Comment.minimum(:id)..Comment.maximum(:id))).limit(1).first
    comment.destroy!
    @post = comment.post
    render "posts/show", status: :ok
  end

  def post_show
    @post = Post.where("id >= ?", rand(Post.minimum(:id)..Post.maximum(:id))).limit(1).first
    render "posts/show", status: :ok
  end

  def posts_index
    @posts = Post.where("id >= ?", rand(Post.minimum(:id)..Post.maximum(:id))).limit(100)
    render "posts/index", status: :ok
  end

  def user_show
    render "users/show", status: :ok
  end

  private

    def sign_in_random_user
      @user = User.where("id >= ?", rand(User.minimum(:id)..User.maximum(:id))).limit(1).first
      start_new_session_for @user
    end

    def format(request:)
      request.headers.to_h.slice(
        "GATEWAY_INTERFACE",
        "HTTP_ACCEPT",
        "HTTP_HOST",
        "HTTP_USER_AGENT",
        "HTTP_VERSION",
        "ORIGINAL_FULLPATH",
        "ORIGINAL_SCRIPT_NAME",
        "PATH_INFO",
        "QUERY_STRING",
        "REMOTE_ADDR",
        "REQUEST_METHOD",
        "REQUEST_PATH",
        "REQUEST_URI",
        "SCRIPT_NAME",
        "SERVER_NAME",
        "SERVER_PORT",
        "SERVER_PROTOCOL",
        "SERVER_SOFTWARE",
        "action_dispatch.request_id",
        "puma.request_body_wait",
      ).map { _1.join(": ") }.join("\n")
    end
end
