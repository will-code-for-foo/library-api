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
  end

  it 'rejects a duplicate serial number at the database level' do
    create(:book, serial_number: '000123')
    duplicate = build(:book, serial_number: '000123')

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
