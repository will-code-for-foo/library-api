class Book < ApplicationRecord
  ALREADY_BORROWED = "Book is already borrowed".freeze
  NOT_BORROWED = "Book is not borrowed".freeze
  AVAILABLE = "available".freeze
  BORROWED = "borrowed".freeze
  private_constant :ALREADY_BORROWED, :NOT_BORROWED, :AVAILABLE, :BORROWED

  has_many :loans
  has_one :active_loan, -> { active }, class_name: "Loan"

  validates :serial_number, presence: true, uniqueness: true
  validates :serial_number, format: { with: /\A\d{6}\z/, message: "must be exactly six digits" }, allow_blank: true
  validates :title, :author, presence: true

  # Loads the active loan and its reader together with the books, so that listing books takes a constant number of queries.
  scope :with_current_loan, -> { includes(active_loan: :reader) }

  def status
    active_loan ? BORROWED : AVAILABLE
  end

  def borrow!(reader)
    raise ConflictError, ALREADY_BORROWED if loans.active.exists?

    loans.create!(reader:)
  rescue ActiveRecord::RecordNotUnique
    # A concurrent request borrowed the book after the check above; the unique index on active loans caught it.
    raise ConflictError, ALREADY_BORROWED
  end

  def return!
    transaction do
      # The row lock makes a concurrent return wait, then find no active loan and fail with a conflict.
      loan = loans.active.lock.take
      raise ConflictError, NOT_BORROWED unless loan

      loan.update!(returned_at: Time.current)
      loan
    end
  end
end
