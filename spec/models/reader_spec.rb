require 'rails_helper'

RSpec.describe Reader, type: :model do
  subject(:reader) { build(:reader) }

  it { is_expected.to validate_presence_of(:card_number) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:email) }

  describe 'card_number format' do
    it { is_expected.to allow_values('000123', '123456', '999999').for(:card_number) }
    it { is_expected.not_to allow_values('12345', '1234567', '12345a', '12 345', "123456\n", "123456\nabc", '١٢٣٤٥٦').for(:card_number) }
  end

  describe 'email format' do
    it { is_expected.to allow_values('ann@example.com', 'ann.smith+library@mail.example.org').for(:email) }
    it { is_expected.not_to allow_values('ann', 'ann@', '@example.com', 'ann@@example.com', 'ann example@example.com').for(:email) }
  end

  describe 'email normalization' do
    it 'strips surrounding whitespace and lowercases the email' do
      expect(build(:reader, email: "  Ann@Example.com\n").email).to eq('ann@example.com')
    end

    it 'treats an email of only whitespace as blank' do
      reader = build(:reader, email: '   ')

      expect(reader).not_to be_valid
      expect(reader.errors[:email]).to eq([ "can't be blank" ])
    end
  end

  it 'is invalid with a card number that is already taken' do
    create(:reader, card_number: '000123')
    duplicate = build(:reader, card_number: '000123')

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:card_number]).to eq([ 'has already been taken' ])
  end

  it 'is invalid with an email that is already taken, ignoring case and surrounding whitespace' do
    create(:reader, email: 'ann@example.com')

    [ 'ann@example.com', 'Ann@Example.com', '  ann@example.com ' ].each do |email|
      duplicate = build(:reader, email:)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to eq([ 'has already been taken' ])
    end
  end

  it 'rejects a duplicate card number at the database level' do
    create(:reader, card_number: '000123')
    duplicate = build(:reader, card_number: '000123')

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'rejects a duplicate email at the database level' do
    create(:reader, email: 'ann@example.com')
    duplicate = build(:reader, email: 'Ann@Example.com')

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
