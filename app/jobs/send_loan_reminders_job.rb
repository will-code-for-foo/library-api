# Emails the readers whose books are due soon (see Loan::REMINDERS). Runs once a day (config/recurring.yml); a reminder
# that was already sent is never sent again, so running it more often is harmless.
class SendLoanRemindersJob < ApplicationJob
  queue_as :default

  def perform(today = Date.current)
    Loan::REMINDERS.each_key do |kind|
      Loan.awaiting_reminder(kind, today).includes(:book, :reader).find_each do |loan|
        send_reminder(loan, kind) if loan.claim_reminder(kind)
      end
    end
  end

  private

  # A failing email must not stop the other readers from being reminded: the reminder is given back, so that a
  # later run of the job picks it up again, and the error is logged.
  def send_reminder(loan, kind)
    LoanMailer.reminder(loan, kind).deliver_now
  rescue StandardError => error
    loan.release_reminder(kind)
    Rails.logger.error("Could not send the #{kind} reminder of loan #{loan.id}: #{error.class}: #{error.message}")
  end
end
