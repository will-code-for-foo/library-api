require 'rails_helper'

RSpec.describe Loan, type: :model do
  subject(:loan) { build(:loan) }

  it { is_expected.to belong_to(:book) }
  it { is_expected.to belong_to(:reader) }

  describe 'dates' do
    it 'borrows at the current time and is due 30 days later' do
      travel_to Time.zone.local(2026, 10, 21, 12, 30) do
        loan = create(:loan, borrowed_at: nil)

        expect(loan.borrowed_at).to eq(Time.zone.local(2026, 10, 21, 12, 30))
        expect(loan.due_on).to eq(Date.new(2026, 11, 20))
      end
    end

    it 'counts the 30 days across the end of a month and a year' do
      expect(create(:loan, borrowed_at: Time.zone.local(2026, 1, 31, 9)).due_on).to eq(Date.new(2026, 3, 2))
      expect(create(:loan, borrowed_at: Time.zone.local(2026, 12, 15, 23, 59)).due_on).to eq(Date.new(2027, 1, 14))
    end

    it 'is due 30 days after the borrow date, not 30 times 24 hours after the borrow time' do
      loan = create(:loan, borrowed_at: Time.zone.local(2026, 10, 21, 23, 59))

      expect(loan.due_on).to eq(Date.new(2026, 11, 20))
    end
  end

  describe '#overdue?' do
    let(:loan) { create(:loan, borrowed_at: Time.zone.local(2026, 10, 1, 12)) }

    it 'is false before the due date' do
      travel_to(Time.zone.local(2026, 10, 30)) { expect(loan).not_to be_overdue }
    end

    it 'is false on the due date' do
      travel_to(Time.zone.local(2026, 10, 31, 23, 59)) { expect(loan).not_to be_overdue }
    end

    it 'is true after the due date while the book is not returned' do
      travel_to(Time.zone.local(2026, 11, 1)) { expect(loan).to be_overdue }
    end

    it 'is false for a loan that was returned late' do
      loan.update!(returned_at: Time.zone.local(2026, 11, 5))

      travel_to(Time.zone.local(2026, 12, 1)) { expect(loan).not_to be_overdue }
    end
  end

describe 'reminders' do
  let(:borrowed_at) { Time.zone.local(2026, 10, 1, 12) } # due on 2026-10-31
  let(:loan) { create(:loan, borrowed_at:) }

  it 'knows when each reminder goes out and where it records that it was sent' do
    expect(described_class::REMINDERS).to eq(
      three_days: { days_before_due: 3, sent_at: :three_days_reminder_sent_at },
      due_date: { days_before_due: 0, sent_at: :due_date_reminder_sent_at }
    )
  end

  { three_days: Date.new(2026, 10, 28), due_date: Date.new(2026, 10, 31) }.each do |kind, day|
    describe ".awaiting_reminder(:#{kind}, day)" do
      let(:sent_at) { described_class::REMINDERS.fetch(kind)[:sent_at] }

      it 'finds the active loans due on the right day that were not reminded yet' do
        loan
        create(:loan, borrowed_at: borrowed_at + 1.day)
        create(:loan, :returned, borrowed_at:)
        create(:loan, borrowed_at:, sent_at => Time.current)

        expect(described_class.awaiting_reminder(kind, day)).to contain_exactly(loan)
      end

      it 'finds nothing on any other day' do
        loan

        other_days = (Date.new(2026, 10, 1)..Date.new(2026, 11, 30)).to_a - [ day ]

        expect(other_days.flat_map { |other_day| described_class.awaiting_reminder(kind, other_day).to_a }).to be_empty
      end
    end
  end

  it 'does not know a reminder that is not in REMINDERS' do
    expect { described_class.awaiting_reminder(:next_week, Date.new(2026, 10, 28)) }.to raise_error(KeyError)
    expect { loan.claim_reminder(:next_week) }.to raise_error(KeyError)
    expect { loan.release_reminder(:next_week) }.to raise_error(KeyError)
  end

  describe '#claim_reminder' do
    it 'is true only for the first caller' do
      expect(loan.claim_reminder(:three_days)).to be(true)
      expect(loan.claim_reminder(:three_days)).to be(false)
      expect(described_class.find(loan.id).three_days_reminder_sent_at).to be_present
    end

    it 'is false for a copy of the loan loaded before the reminder was claimed' do
      stale = described_class.find(loan.id)
      loan.claim_reminder(:three_days)

      expect(stale.claim_reminder(:three_days)).to be(false)
    end

    it 'is false, and claims nothing, for a loan that was returned after it was loaded' do
      stale = described_class.find(loan.id)
      loan.update!(returned_at: Time.current)

      expect(stale.claim_reminder(:three_days)).to be(false)
      expect(described_class.find(loan.id).three_days_reminder_sent_at).to be_nil
    end

    it 'claims the reminders independently' do
      loan.claim_reminder(:three_days)

      expect(loan.claim_reminder(:due_date)).to be(true)
    end
  end

  describe '#release_reminder' do
    it 'makes a claimed reminder claimable again, leaving the other reminder alone' do
      loan.claim_reminder(:three_days)
      loan.claim_reminder(:due_date)

      loan.release_reminder(:three_days)

      reloaded = described_class.find(loan.id)
      expect(reloaded.three_days_reminder_sent_at).to be_nil
      expect(reloaded.due_date_reminder_sent_at).to be_present
      expect(loan.claim_reminder(:three_days)).to be(true)
    end
  end
end

  describe '.active' do
    it 'returns only the loans that were not returned' do
      active = create(:loan)
      create(:loan, :returned)

      expect(described_class.active).to contain_exactly(active)
    end
  end

  describe 'one active loan per book' do
    let(:book) { create(:book) }

    it 'rejects a second active loan for the same book at the database level' do
      create(:loan, book:)

      expect { create(:loan, book:) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows a new loan once the previous one was returned' do
      create(:loan, :returned, book:)

      expect { create(:loan, book:) }.not_to raise_error
    end

    it 'allows any number of returned loans for the same book' do
      expect { create_list(:loan, 3, :returned, book:) }.not_to raise_error
    end

    it 'allows different books to be borrowed at the same time' do
      expect { create_list(:loan, 3) }.not_to raise_error
    end
  end
end
