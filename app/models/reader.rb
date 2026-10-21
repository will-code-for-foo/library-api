class Reader < ApplicationRecord
  validates :card_number, presence: true, uniqueness: true
  validates :card_number, format: { with: /\A\d{6}\z/, message: "must be exactly six digits" }, allow_blank: true
  validates :name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "is not a valid email address" }, allow_blank: true
end
