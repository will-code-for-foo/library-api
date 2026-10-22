require "rails_helper"

RSpec.describe LogDelivery do
  let(:log) { StringIO.new }
  let(:loan) do
    create(:loan,
           book: create(:book, serial_number: "000123", title: "Clean Code"),
           reader: create(:reader, name: "Ann Kowalska", email: "ann@example.com"))
  end

  around do |example|
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :log
    example.run
  ensure
    ActionMailer::Base.delivery_method = original
  end

  before do
    ActionMailer::Base.deliveries.clear
    logger = ActiveSupport::Logger.new(log)
    logger.formatter = proc { |severity, _time, _progname, message| "#{severity}: #{message}" }
    allow(Rails).to receive(:logger).and_return(logger)
  end

  it "is registered as the :log delivery method" do
    expect(ActionMailer::Base.delivery_methods[:log]).to eq(described_class)
  end

  it "writes from, to, subject and body of the delivered email to the log at INFO level and sends it nowhere" do
    expect(Mail::SMTP).not_to receive(:new)
    expect(Mail::Sendmail).not_to receive(:new)
    expect(TCPSocket).not_to receive(:open)
    expect(Socket).not_to receive(:tcp)

    LoanMailer.due_date_reminder(loan).deliver_now

    expect(log.string).to start_with("INFO: Email not sent, logged instead")
    expect(log.string).to include(
      "From: library@example.com",
      "To: Ann Kowalska <ann@example.com>",
      'Subject: Reminder: "Clean Code" is due today',
      '"Clean Code" by'
    )
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "logs every email it delivers" do
    LoanMailer.three_days_reminder(loan).deliver_now
    LoanMailer.due_date_reminder(loan).deliver_now

    expect(log.string.scan("Email not sent, logged instead").size).to eq(2)
  end
end
