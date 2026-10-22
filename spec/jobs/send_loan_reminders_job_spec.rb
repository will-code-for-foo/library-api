require 'rails_helper'

RSpec.describe SendLoanRemindersJob, type: :job do
  let(:borrowed_at) { Time.zone.local(2026, 10, 1, 12) } # due on 2026-10-31, 30 days later
  let(:three_days_before) { Date.new(2026, 10, 28) }
  let(:due_date) { Date.new(2026, 10, 31) }
  let(:reader) { create(:reader, name: 'Ann Kowalska', email: 'ann@example.com') }
  let!(:loan) { create(:loan, book: create(:book, title: 'Clean Code'), reader:, borrowed_at:) }

  def run_on(date)
    described_class.perform_now(date)
  end

  def sent
    ActionMailer::Base.deliveries
  end

  before { sent.clear }

  it 'emails the reader 3 days before the due date' do
    run_on(three_days_before)

    expect(sent.size).to eq(1)
    expect(sent.first.to).to eq([ 'ann@example.com' ])
    expect(sent.first.subject).to eq('Reminder: "Clean Code" is due in 3 days (2026-10-31)')
  end

  it 'emails the reader on the due date' do
    run_on(due_date)

    expect(sent.size).to eq(1)
    expect(sent.first.to).to eq([ 'ann@example.com' ])
    expect(sent.first.subject).to eq('Reminder: "Clean Code" is due today (2026-10-31)')
  end

  it 'sends one email on day 27 and one on day 30 of the loan and nothing on other days' do
    sent_on = {}
    (borrowed_at.to_date..borrowed_at.to_date + 40).each do |day|
      sent.clear
      run_on(day)
      sent_on[day] = sent.map(&:subject)
    end

    expect(sent_on.reject { |_day, subjects| subjects.empty? }).to eq(
      three_days_before => [ 'Reminder: "Clean Code" is due in 3 days (2026-10-31)' ],
      due_date => [ 'Reminder: "Clean Code" is due today (2026-10-31)' ]
    )
  end

  it 'uses the current date when it is not given one' do
    travel_to(Time.zone.local(2026, 10, 28, 8)) { described_class.perform_now }

    expect(sent.size).to eq(1)
  end

  it 'sends each reminder at most once, however often it runs' do
    3.times { run_on(three_days_before) }
    3.times { run_on(due_date) }

    expect(sent.map(&:subject)).to eq([
      'Reminder: "Clean Code" is due in 3 days (2026-10-31)',
      'Reminder: "Clean Code" is due today (2026-10-31)'
    ])
  end

  it 'remembers which reminder was sent' do
    run_on(three_days_before)

    expect(loan.reload.three_days_reminder_sent_at).to be_present
    expect(loan.due_date_reminder_sent_at).to be_nil
  end

  it 'sends nothing for a loan returned before the reminder date' do
    loan.update!(returned_at: Time.zone.local(2026, 10, 20))

    run_on(three_days_before)
    run_on(due_date)

    expect(sent).to be_empty
  end

  it 'sends no due date reminder for a loan returned after the 3 days reminder' do
    run_on(three_days_before)
    loan.update!(returned_at: Time.zone.local(2026, 10, 29))
    run_on(due_date)

    expect(sent.size).to eq(1)
  end

  it 'sends two emails to a reader with two loans due on the same day' do
    create(:loan, book: create(:book, title: 'Refactoring'), reader:, borrowed_at:)

    run_on(three_days_before)

    expect(sent.map(&:subject)).to contain_exactly(
      'Reminder: "Clean Code" is due in 3 days (2026-10-31)',
      'Reminder: "Refactoring" is due in 3 days (2026-10-31)'
    )
  end

  it 'does not touch loans that are not due on that day' do
    other = create(:loan, borrowed_at: borrowed_at + 2.days)

    run_on(three_days_before)

    expect(other.reload.three_days_reminder_sent_at).to be_nil
    expect(sent.size).to eq(1)
  end

  context 'when the email of one loan cannot be sent' do
    let!(:other_loan) { create(:loan, book: create(:book, title: 'Refactoring'), reader:, borrowed_at: borrowed_at + 1.second) }
    let(:failing) { true }

    before do
      allow(Rails.logger).to receive(:error)
      allow(LoanMailer).to receive(:reminder).and_wrap_original do |original, loan_to_remind, kind|
        raise 'mail server down' if failing && loan_to_remind.id == loan.id

        original.call(loan_to_remind, kind)
      end
    end

    it 'still reminds the other readers and logs the error' do
      run_on(three_days_before)

      expect(sent.map(&:subject)).to eq([ 'Reminder: "Refactoring" is due in 3 days (2026-10-31)' ])
      expect(Rails.logger).to have_received(:error).with(/three_days reminder of loan #{loan.id}: RuntimeError: mail server down/)
    end

    it 'gives the reminder back, so that the next run sends it and nothing else again' do
      run_on(three_days_before)
      expect(loan.reload.three_days_reminder_sent_at).to be_nil
      expect(other_loan.reload.three_days_reminder_sent_at).to be_present

      allow(LoanMailer).to receive(:reminder).and_call_original
      run_on(three_days_before)

      expect(sent.map(&:subject)).to eq([
        'Reminder: "Refactoring" is due in 3 days (2026-10-31)',
        'Reminder: "Clean Code" is due in 3 days (2026-10-31)'
      ])
    end
  end
end
