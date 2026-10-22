require "rails_helper"

RSpec.describe LoanMailer, type: :mailer do
  let(:reader) { create(:reader, name: "Ann Kowalska", email: "ann@example.com") }
  let(:book) { create(:book, serial_number: "000123", title: "Clean Code", author: "Robert C. Martin") }
  let(:loan) { create(:loan, book:, reader:, borrowed_at: Time.zone.local(2026, 10, 1, 12)) }

  shared_examples "a reminder about the loan" do
    it "is sent from the library to the reader" do
      expect(mail.from).to eq([ "library@example.com" ])
      expect(mail.to).to eq([ "ann@example.com" ])
      expect(mail[:to].to_s).to eq("Ann Kowalska <ann@example.com>")
    end

    it "names the book title and the due date in the subject" do
      expect(mail.subject).to include('"Clean Code"', "2026-10-31")
    end

    it "gives the reader name, title, author, serial number and due date in the body" do
      expect(mail.body.encoded).to include("Ann Kowalska", "Clean Code", "Robert C. Martin", "000123", "2026-10-31")
    end

    it "is a plain text email" do
      expect(mail.content_type).to start_with("text/plain")
    end
  end

  describe "three_days_reminder" do
    let(:mail) { described_class.three_days_reminder(loan) }

    it_behaves_like "a reminder about the loan"

    it "says that the book is due in 3 days" do
      expect(mail.subject).to eq('Reminder: "Clean Code" is due in 3 days (2026-10-31)')
      expect(mail.body.encoded).to include("is due in 3 days, on 2026-10-31")
    end
  end

  describe "due_date_reminder" do
    let(:mail) { described_class.due_date_reminder(loan) }

    it_behaves_like "a reminder about the loan"

    it "says that the book is due today" do
      expect(mail.subject).to eq('Reminder: "Clean Code" is due today (2026-10-31)')
      expect(mail.body.encoded).to include("is due today, 2026-10-31")
    end
  end

  describe "previews" do
    # Only development has spec/mailers/previews among its preview paths, so load the preview by hand.
    before { require Rails.root.join("spec/mailers/previews/loan_mailer_preview") }

    it "build both emails without touching the database" do
      expect(LoanMailerPreview.new.three_days_reminder.subject).to include("is due in 3 days")
      expect(LoanMailerPreview.new.due_date_reminder.subject).to include("is due today")
    end
  end
end
