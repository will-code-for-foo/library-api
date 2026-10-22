class LoanMailer < ApplicationMailer
  # Reminds the reader of `loan` that the book is due; `kind` is a key of Loan::REMINDERS.
  def reminder(loan, kind)
    @loan = loan
    @due = due_phrase(Loan::REMINDERS.fetch(kind)[:days_before_due])

    mail to: email_address_with_name(loan.reader.email, loan.reader.name),
         subject: %(Reminder: "#{loan.book.title}" is due #{@due} (#{loan.due_on}))
  end

  private

  def due_phrase(days_before_due)
    days_before_due.zero? ? "today" : "in #{days_before_due} #{'day'.pluralize(days_before_due)}"
  end
end
