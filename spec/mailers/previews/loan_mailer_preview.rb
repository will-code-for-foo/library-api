# Preview all emails at http://localhost:3000/rails/mailers/loan_mailer
# Every reminder of Loan::REMINDERS has a preview named after it, e.g. /rails/mailers/loan_mailer/three_days
class LoanMailerPreview < ActionMailer::Preview
  Loan::REMINDERS.each_key do |kind|
    define_method(kind) { LoanMailer.reminder(sample_loan(kind), kind) }
  end

  private

  def sample_loan(kind)
    due_on = Date.current + Loan::REMINDERS.fetch(kind)[:days_before_due]

    Loan.new(
      book: Book.new(serial_number: "000123", title: "Clean Code", author: "Robert C. Martin"),
      reader: Reader.new(card_number: "000456", name: "Ann Kowalska", email: "ann@example.com"),
      borrowed_at: due_on.in_time_zone - Loan::LOAN_PERIOD,
      due_on:
    )
  end
end
