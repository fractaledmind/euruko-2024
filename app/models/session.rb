class Session < ApplicationRecord
  belongs_to :user

  def browser = @browser ||= Browser.new(user_agent)
end
