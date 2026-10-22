class Book < ApplicationRecord
  ALREADY_BORROWED = "Book is already borrowed".freeze
  NOT_BORROWED = "Book is not borrowed".freeze
  BORROWED_CANNOT_BE_DELETED = "Borrowed book cannot be deleted".freeze
  AVAILABLE = "available".freeze
  BORROWED = "borrowed".freeze
  private_constant :ALREADY_BORROWED, :NOT_BORROWED, :BORROWED_CANNOT_BE_DELETED, :AVAILABLE, :BORROWED

  has_many :loans, dependent: :delete_all
  has_one :active_loan, -> { active }, class_name: "Loan"
  has_many :loan_history, -> { newest_first }, class_name: "Loan"

  validates :serial_number, presence: true, uniqueness: true
  validates :serial_number, format: { with: /\A\d{6}\z/, message: "must be exactly six digits" }, allow_blank: true
  validates :title, :author, presence: true

  # Loads the active loan and its reader together with the books, so that listing books takes a constant number of queries.
  scope :with_current_loan, -> { includes(active_loan: :reader) }
  # Same for the borrowing history, so that showing a book takes a constant number of queries however many loans it has.
  scope :with_loan_history, -> { includes(loan_history: :reader) }

  # Reads the preloaded active loan, which is what lets a list of books be shown without a query per book.
  def status
    active_loan ? BORROWED : AVAILABLE
  end

  # Asks the database, so it can be trusted for a decision even when the active loan was loaded earlier.
  def borrowed?
    loans.active.exists?
  end

  def borrow!(reader)
    raise ConflictError, ALREADY_BORROWED if borrowed?

    loans.create!(reader:)
  rescue ActiveRecord::RecordNotUnique
    # A concurrent request borrowed the book after the check above; the unique index on active loans caught it.
    raise ConflictError, ALREADY_BORROWED
  rescue ActiveRecord::InvalidForeignKey
    # A concurrent request deleted the book after it was loaded.
    raise ActiveRecord::RecordNotFound.new(nil, self.class.name)
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

  def remove!
    transaction do
      # The row lock makes a concurrent borrow wait, so no loan can appear between the check and the delete.
      lock!
      raise ConflictError, BORROWED_CANNOT_BE_DELETED if borrowed?

      destroy!
    end
  end
end
