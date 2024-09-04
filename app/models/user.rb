class User < ApplicationRecord
  has_secure_password

  validates :screen_name, presence: true, uniqueness: true
end
