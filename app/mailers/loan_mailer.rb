class LoanMailer < ApplicationMailer
  def three_days_reminder(loan)
    @loan = loan

    mail to: recipient, subject: %(Reminder: "#{loan.book.title}" is due in 3 days (#{loan.due_on}))
  end

  def due_date_reminder(loan)
    @loan = loan

    mail to: recipient, subject: %(Reminder: "#{loan.book.title}" is due today (#{loan.due_on}))
  end

  private

  def recipient
    email_address_with_name(@loan.reader.email, @loan.reader.name)
  end
end
