class Reader < ApplicationRecord
  # Emails are stored trimmed and lowercased, so the unique index also rejects `Ann@Example.com` next to `ann@example.com`.
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :card_number, presence: true, uniqueness: true
  validates :card_number, format: { with: /\A\d{6}\z/, message: "must be exactly six digits" }, allow_blank: true
  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "is not a valid email address" }, allow_blank: true
end
