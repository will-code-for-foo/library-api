class Book < ApplicationRecord
  validates :serial_number, presence: true, uniqueness: true
  validates :serial_number, format: { with: /\A\d{6}\z/, message: "must be exactly six digits" }, allow_blank: true
  validates :title, :author, presence: true
end
