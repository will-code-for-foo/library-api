# Preview all emails at http://localhost:3000/rails/mailers/loan_mailer
class LoanMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/loan_mailer/three_days_reminder
  def three_days_reminder
    LoanMailer.three_days_reminder(sample_loan(due_in: 3))
  end

  # Preview this email at http://localhost:3000/rails/mailers/loan_mailer/due_date_reminder
  def due_date_reminder
    LoanMailer.due_date_reminder(sample_loan(due_in: 0))
  end

  private

  def sample_loan(due_in:)
    Loan.new(
      book: Book.new(serial_number: "000123", title: "Clean Code", author: "Robert C. Martin"),
      reader: Reader.new(card_number: "000456", name: "Ann Kowalska", email: "ann@example.com"),
      borrowed_at: (30 - due_in).days.ago,
      due_on: Date.current + due_in
    )
  end
end
