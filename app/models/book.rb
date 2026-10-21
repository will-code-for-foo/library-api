class Book < ApplicationRecord
  ALREADY_BORROWED = "Book is already borrowed".freeze
  private_constant :ALREADY_BORROWED

  has_many :loans

  validates :serial_number, presence: true, uniqueness: true
  validates :serial_number, format: { with: /\A\d{6}\z/, message: "must be exactly six digits" }, allow_blank: true
  validates :title, :author, presence: true

  def borrow!(reader)
    raise ConflictError, ALREADY_BORROWED if loans.active.exists?

    loans.create!(reader:)
  rescue ActiveRecord::RecordNotUnique
    # A concurrent request borrowed the book after the check above; the unique index on active loans caught it.
    raise ConflictError, ALREADY_BORROWED
  end
end
