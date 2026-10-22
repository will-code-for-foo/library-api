class Loan < ApplicationRecord
  LOAN_PERIOD = 30.days

  belongs_to :book
  belongs_to :reader

  before_validation :set_dates, on: :create

  validates :borrowed_at, :due_on, presence: true

  scope :active, -> { where(returned_at: nil) }

  def overdue?
    returned_at.nil? && due_on < Date.current
  end

  private

  def set_dates
    self.borrowed_at ||= Time.current
    self.due_on ||= (borrowed_at + LOAN_PERIOD).to_date
  end
end
