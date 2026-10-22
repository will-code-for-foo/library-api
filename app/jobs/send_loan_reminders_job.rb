# Emails the readers whose books are due in 3 days or today. Runs once a day (config/recurring.yml); a reminder
# that was already sent is never sent again, so running it more often is harmless.
class SendLoanRemindersJob < ApplicationJob
  queue_as :default

  def perform
    today = Date.current

    Loan.awaiting_three_days_reminder(today).includes(:book, :reader).find_each do |loan|
      LoanMailer.three_days_reminder(loan).deliver_now if loan.mark_reminder_sent(:three_days_reminder_sent_at)
    end

    Loan.awaiting_due_date_reminder(today).includes(:book, :reader).find_each do |loan|
      LoanMailer.due_date_reminder(loan).deliver_now if loan.mark_reminder_sent(:due_date_reminder_sent_at)
    end
  end
end
