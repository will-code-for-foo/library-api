require 'rails_helper'

RSpec.describe Book, type: :model do
  subject(:book) { build(:book) }

  it { is_expected.to validate_presence_of(:serial_number) }
  it { is_expected.to validate_presence_of(:title) }
  it { is_expected.to validate_presence_of(:author) }

  describe 'serial_number format' do
    it { is_expected.to allow_values('000123', '123456', '999999').for(:serial_number) }
    it { is_expected.not_to allow_values('12345', '1234567', '12345a', '12 345', "123456\n", "123456\nabc", '١٢٣٤٥٦').for(:serial_number) }
  end

  it 'is invalid with a serial number that is already taken' do
    create(:book, serial_number: '000123')
    duplicate = build(:book, serial_number: '000123')

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:serial_number]).to eq([ 'has already been taken' ])
  end

  describe '#status' do
    let(:book) { create(:book) }

    it 'is available when the book has no loans' do
      expect(book.status).to eq('available')
    end

    it 'is available when all loans were returned' do
      create(:loan, :returned, book:)

      expect(book.status).to eq('available')
    end

    it 'is borrowed while a loan is active' do
      create(:loan, book:)

      expect(book.status).to eq('borrowed')
    end
  end

  describe '.with_current_loan' do
    it 'loads the active loans with their readers without a query per book' do
      create_list(:loan, 3)
      create(:loan, :returned)

      books = described_class.with_current_loan.to_a
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' }
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        books.each { |book| book.active_loan&.reader&.name }
      end

      expect(queries).to eq(0)
      expect(books.count(&:active_loan)).to eq(3)
    end
  end

  describe '#loan_history' do
    let(:book) { create(:book) }

    it 'lists the loans of the book from the most recently borrowed' do
      newest = create(:loan, book:, borrowed_at: Time.zone.local(2026, 10, 1))
      oldest = create(:loan, :returned, book:, borrowed_at: Time.zone.local(2026, 8, 1))
      middle = create(:loan, :returned, book:, borrowed_at: Time.zone.local(2026, 9, 1))

      expect(book.loan_history).to eq([ newest, middle, oldest ])
    end

    it 'puts the loan created later first when two loans were borrowed at the same moment' do
      moment = Time.zone.local(2026, 9, 1)
      first = create(:loan, :returned, book:, borrowed_at: moment)
      second = create(:loan, :returned, book:, borrowed_at: moment)

      expect(book.loan_history).to eq([ second, first ])
    end

    it 'does not include the loans of other books' do
      create(:loan)

      expect(book.loan_history).to be_empty
    end
  end

  describe '#borrow!' do
    let(:book) { create(:book) }
    let(:reader) { create(:reader) }

    it 'creates an active loan for the reader' do
      loan = nil

      expect { loan = book.borrow!(reader) }.to change(Loan, :count).by(1)
      expect(loan).to have_attributes(book:, reader:, returned_at: nil)
    end

    it 'raises a conflict and creates no loan when the book is already borrowed' do
      create(:loan, book:)

      expect { book.borrow!(reader) }.to raise_error(ConflictError, 'Book is already borrowed')
      expect(Loan.count).to eq(1)
    end

    it 'lets the book be borrowed again once it was returned' do
      create(:loan, :returned, book:)

      expect { book.borrow!(reader) }.to change(Loan, :count).by(1)
    end

    it 'raises a conflict when another request borrows the book after the check' do
      create(:loan, book:)
      allow(Loan).to receive(:active).and_return(Loan.none)

      expect { book.borrow!(reader) }.to raise_error(ConflictError, 'Book is already borrowed')
      expect(Loan.count).to eq(1)
    end

    it 'raises not found when the book was deleted after it was loaded' do
      described_class.delete(book.id)

      expect { book.borrow!(reader) }.to raise_error(ActiveRecord::RecordNotFound) { |error| expect(error.model).to eq('Book') }
    end
  end

  describe '#remove!' do
    let(:book) { create(:book) }

    it 'deletes an available book' do
      book.remove!

      expect(described_class.exists?(book.id)).to be(false)
    end

    it 'deletes the loan history of the book with it and leaves the loans of other books' do
      create_list(:loan, 2, :returned, book:)
      other = create(:loan)

      expect { book.remove! }.to change(Loan, :count).by(-2)
      expect(other.reload).to be_present
    end

    it 'raises a conflict and deletes nothing when the book is borrowed' do
      loan = create(:loan, book:)
      create(:loan, :returned, book:, borrowed_at: 3.days.ago)

      expect { book.remove! }.to raise_error(ConflictError, 'Borrowed book cannot be deleted')
      expect(described_class.exists?(book.id)).to be(true)
      expect(Loan.where(book:).count).to eq(2)
      expect(loan.reload.returned_at).to be_nil
    end

    it 'raises not found when the book was already deleted' do
      described_class.delete(book.id)

      expect { book.remove! }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#return!' do
    let(:book) { create(:book) }

    it 'closes the active loan and returns it' do
      loan = create(:loan, book:)

      returned = travel_to(Time.zone.local(2026, 10, 24, 9, 15)) { book.return! }

      expect(returned).to eq(loan)
      expect(loan.reload.returned_at).to eq(Time.zone.local(2026, 10, 24, 9, 15))
    end

    it 'raises a conflict when the book was never borrowed' do
      expect { book.return! }.to raise_error(ConflictError, 'Book is not borrowed')
    end

    it 'raises a conflict when the book was already returned' do
      create(:loan, :returned, book:)

      expect { book.return! }.to raise_error(ConflictError, 'Book is not borrowed')
    end

    it 'does not change the loans of other books' do
      create(:loan, book:)
      other = create(:loan)

      book.return!

      expect(other.reload.returned_at).to be_nil
    end
  end

  it 'rejects a duplicate serial number at the database level' do
    create(:book, serial_number: '000123')
    duplicate = build(:book, serial_number: '000123')

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
