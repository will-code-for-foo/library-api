class Loan < ApplicationRecord
  LOAN_PERIOD = 30.days

  belongs_to :book
  belongs_to :reader

  before_validation :set_dates, on: :create

  validates :borrowed_at, :due_on, presence: true

  scope :active, -> { where(returned_at: nil) }
  scope :newest_first, -> { order(borrowed_at: :desc, id: :desc) }
  # Loans whose reader still has to be reminded on `today`: the book is not returned, the due date is 3 days away
  # (or today) and that reminder was not sent yet.
  scope :awaiting_three_days_reminder, ->(today) { active.where(due_on: today + 3, three_days_reminder_sent_at: nil) }
  scope :awaiting_due_date_reminder, ->(today) { active.where(due_on: today, due_date_reminder_sent_at: nil) }

  def overdue?
    returned_at.nil? && due_on < Date.current
  end

  # Marks a reminder (`three_days_reminder_sent_at` or `due_date_reminder_sent_at`) as sent. It is a single conditional
  # update, so only one of any number of repeated or concurrent callers gets `true` and may send the email.
  def mark_reminder_sent(column)
    self.class.where(id:, column => nil).update_all(column => Time.current) == 1
  end

  private

  def set_dates
    self.borrowed_at ||= Time.current
    self.due_on ||= (borrowed_at + LOAN_PERIOD).to_date
  end
end
