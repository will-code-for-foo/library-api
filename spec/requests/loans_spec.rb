require 'rails_helper'

RSpec.describe 'Loans', type: :request do
  describe 'POST /books/:book_id/loans' do
    let(:book) { create(:book, serial_number: '000123') }
    let(:reader) { create(:reader, card_number: '000456', name: 'Ann Kowalska', email: 'ann@example.com') }
    let(:params) { { card_number: reader.card_number } }

    def borrow(book_id: book.id, params: self.params)
      post "/books/#{book_id}/loans", params:, as: :json
    end

    def error
      response.parsed_body['error']
    end

    context 'when the book is available' do
      it 'creates the loan and responds with 201 and the loan' do
        travel_to Time.zone.local(2026, 10, 21, 12, 30) do
          expect { borrow }.to change(Loan, :count).by(1)
        end

        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to eq(
          'book' => { 'id' => book.id, 'serial_number' => '000123' },
          'reader' => { 'card_number' => '000456', 'name' => 'Ann Kowalska', 'email' => 'ann@example.com' },
          'borrowed_at' => '2026-10-21T12:30:00.000Z',
          'due_on' => '2026-11-20',
          'returned_at' => nil
        )
      end

      it 'stores the book, the reader, the borrow time and the due date' do
        travel_to Time.zone.local(2026, 10, 21, 12, 30) do
          borrow
        end

        expect(Loan.last).to have_attributes(
          book:, reader:, borrowed_at: Time.zone.local(2026, 10, 21, 12, 30), due_on: Date.new(2026, 11, 20), returned_at: nil
        )
      end

      it 'finds the reader by card number with leading zeros' do
        borrow

        expect(response.parsed_body.dig('reader', 'card_number')).to eq('000456')
      end

      it 'lets the book be borrowed again after it was returned, keeping the old loan' do
        create(:loan, :returned, book:)

        expect { borrow }.to change(Loan, :count).by(1)
        expect(response).to have_http_status(:created)
      end
    end

    context 'when the book is already borrowed' do
      let!(:borrower) { create(:reader) }

      before { create(:loan, book:, reader: borrower) }

      it 'responds with 409 conflict and creates no loan' do
        expect { borrow }.not_to change(Loan, :count)

        expect(response).to have_http_status(:conflict)
        expect(error).to include('code' => 'conflict', 'message' => 'Book is already borrowed')
      end

      it 'responds with 409 also to the reader who already has the book' do
        expect { borrow(params: { card_number: borrower.card_number }) }.not_to change(Loan, :count)

        expect(response).to have_http_status(:conflict)
      end
    end

    context 'when the book is unknown' do
      it 'responds with 404' do
        expect { borrow(book_id: 0) }.not_to change(Loan, :count)

        expect(response).to have_http_status(:not_found)
        expect(error).to include('code' => 'not_found', 'message' => 'Book not found')
      end

      %w[abc .5].each do |suffix|
        it "responds with 404 and creates no loan when #{suffix.inspect} follows the id of an existing book" do
          expect { borrow(book_id: "#{book.id}#{suffix}") }.not_to change(Loan, :count)

          expect(response).to have_http_status(:not_found)
          expect(error['code']).to eq('not_found')
        end
      end
    end

    context 'when the card number is unknown' do
      it 'responds with 404 and creates no loan' do
        expect { borrow(params: { card_number: '999999' }) }.not_to change(Loan, :count)

        expect(response).to have_http_status(:not_found)
        expect(error).to include('code' => 'not_found', 'message' => 'Reader not found')
      end
    end

    context 'when the card number is missing' do
      [ {}, { card_number: '' }, { card_number: ' ' }, { card_number: nil }, { card_number: { a: 1 } }, { card_number: [ '000456' ] } ].each do |invalid|
        it "responds with 400 parameter_missing for #{invalid.inspect}" do
          expect { borrow(params: invalid) }.not_to change(Loan, :count)

          expect(response).to have_http_status(:bad_request)
          expect(error['code']).to eq('parameter_missing')
        end
      end
    end
  end

  describe 'concurrent borrow requests for the same book' do
    include_context 'with concurrent requests'

    let!(:book) { create(:book) }
    let!(:readers) { create_list(:reader, 3) }

    it 'creates exactly one loan and answers the others with 409' do
      # Holds every request after its "is the book borrowed?" check until all of them have passed it,
      # so that all of them try to insert a loan and only the unique index can stop the extra ones.
      responses = line_up_at_sql(/\ASELECT 1 AS one FROM "loans"/, requests: readers.size, at: :finish) do
        readers.map do |reader|
          request_in_thread(:post, "/books/#{book.id}/loans", json: { card_number: reader.card_number })
        end.map(&:value)
      end

      expect(responses.map(&:status)).to contain_exactly(201, 409, 409)
      expect(Loan.where(book:).count).to eq(1)
      expect(Loan.where(book:).active.count).to eq(1)
    end
  end
end
