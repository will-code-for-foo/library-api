class Loan < ApplicationRecord
  LOAN_PERIOD = 30.days

  # The reminders emailed to the reader: how many days before the due date each one goes out, and the column that
  # records when it was sent.
  REMINDERS = {
    three_days: { days_before_due: 3, sent_at: :three_days_reminder_sent_at },
    due_date: { days_before_due: 0, sent_at: :due_date_reminder_sent_at }
  }.freeze

  belongs_to :book
  belongs_to :reader

  before_validation :set_dates, on: :create

  validates :borrowed_at, :due_on, presence: true

  scope :active, -> { where(returned_at: nil) }
  scope :newest_first, -> { order(borrowed_at: :desc, id: :desc) }

  # Loans whose reader still has to get the reminder `kind` (a key of REMINDERS) on `today`: the book is not returned,
  # the due date is as many days away as that reminder says and the reminder was not sent yet.
  def self.awaiting_reminder(kind, today)
    reminder = REMINDERS.fetch(kind)

    active.where(due_on: today + reminder[:days_before_due], reminder[:sent_at] => nil)
  end

  def overdue?
    returned_at.nil? && due_on < Date.current
  end

  # Claims the reminder `kind` before it is sent. It is a single conditional update, so only one of any number of
  # repeated or concurrent callers gets `true` and may send the email, and only while the book is still borrowed.
  def claim_reminder(kind)
    column = REMINDERS.fetch(kind)[:sent_at]

    self.class.where(id:, returned_at: nil, column => nil).update_all(column => Time.current) == 1
  end

  # Gives a claimed reminder back, e.g. when its email could not be sent, so that it is picked up again.
  def release_reminder(kind)
    self.class.where(id:).update_all(REMINDERS.fetch(kind)[:sent_at] => nil)
  end

  private

  def set_dates
    self.borrowed_at ||= Time.current
    self.due_on ||= (borrowed_at + LOAN_PERIOD).to_date
  end
end
