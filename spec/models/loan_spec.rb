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
