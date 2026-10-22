require 'rails_helper'

RSpec.describe 'Returns', type: :request do
  describe 'POST /books/:book_id/returns' do
    let(:book) { create(:book, serial_number: '000123') }
    let(:reader) { create(:reader, card_number: '000456', name: 'Ann Kowalska', email: 'ann@example.com') }
    let(:borrowed_at) { Time.zone.local(2026, 10, 21, 12, 30) }
    let(:returned_at) { Time.zone.local(2026, 10, 24, 9, 15) }

    def give_back(book_id: book.id)
      post "/books/#{book_id}/returns", as: :json
    end

    def error
      response.parsed_body['error']
    end

    context 'when the book is borrowed' do
      let!(:loan) { create(:loan, book:, reader:, borrowed_at:) }

      it 'closes the loan and responds with 201 and the loan in the shape of the borrow response' do
        travel_to(returned_at) { give_back }

        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to eq(
          'book' => { 'id' => book.id, 'serial_number' => '000123' },
          'reader' => { 'card_number' => '000456', 'name' => 'Ann Kowalska', 'email' => 'ann@example.com' },
          'borrowed_at' => '2026-10-21T12:30:00.000Z',
          'due_on' => '2026-11-20',
          'returned_at' => '2026-10-24T09:15:00.000Z'
        )
      end

      it 'stores the return time on the existing loan instead of creating or deleting one' do
        expect { travel_to(returned_at) { give_back } }.not_to change(Loan, :count)

        expect(loan.reload).to have_attributes(returned_at:, borrowed_at:)
      end

      it 'leaves the loans of other books alone' do
        other_loan = create(:loan)

        give_back

        expect(other_loan.reload.returned_at).to be_nil
      end

      it 'makes the book available again so it can be borrowed again, keeping the old loan' do
        give_back

        expect(book.loans.active).to be_empty
        expect { post "/books/#{book.id}/loans", params: { card_number: reader.card_number }, as: :json }
          .to change(Loan, :count).by(1)
        expect(response).to have_http_status(:created)
        expect(response.parsed_body['returned_at']).to be_nil
        expect(loan.reload.returned_at).to be_present
      end
    end

    context 'when the book is not borrowed' do
      it 'responds with 409 conflict and creates no loan' do
        expect { give_back }.not_to change(Loan, :count)

        expect(response).to have_http_status(:conflict)
        expect(error).to include('code' => 'conflict', 'message' => 'Book is not borrowed')
      end

      it 'responds with 409 conflict for a book whose loans were all returned' do
        create(:loan, :returned, book:)

        give_back

        expect(response).to have_http_status(:conflict)
        expect(error['code']).to eq('conflict')
      end
    end

    context 'when the same loan is returned twice' do
      let!(:loan) { create(:loan, book:, borrowed_at:) }

      it 'responds with 409 conflict the second time and keeps the first return time' do
        travel_to(returned_at) { give_back }
        expect(response).to have_http_status(:created)

        travel_to(returned_at + 1.day) { give_back }

        expect(response).to have_http_status(:conflict)
        expect(error['message']).to eq('Book is not borrowed')
        expect(loan.reload.returned_at).to eq(returned_at)
      end
    end

    context 'when the book is unknown' do
      it 'responds with 404' do
        give_back(book_id: 0)

        expect(response).to have_http_status(:not_found)
        expect(error).to include('code' => 'not_found', 'message' => 'Book not found')
      end

      %w[abc .5].each do |suffix|
        it "responds with 404 and keeps the loan open when #{suffix.inspect} follows the id of a borrowed book" do
          create(:loan, book:)

          give_back(book_id: "#{book.id}#{suffix}")

          expect(response).to have_http_status(:not_found)
          expect(error['code']).to eq('not_found')
          expect(book.loans.active).to exist
        end
      end
    end

    it 'supports the whole cycle: borrow, return, borrow again' do
      post "/books/#{book.id}/loans", params: { card_number: reader.card_number }, as: :json
      expect(response).to have_http_status(:created)

      give_back
      expect(response).to have_http_status(:created)

      post "/books/#{book.id}/loans", params: { card_number: reader.card_number }, as: :json
      expect(response).to have_http_status(:created)
      expect(book.loans.count).to eq(2)
      expect(book.loans.active.count).to eq(1)
    end
  end

  describe 'concurrent return requests for the same book' do
    include_context 'with concurrent requests'

    let!(:book) { create(:book) }
    let!(:loan) { create(:loan, book:) }

    it 'closes the loan once and answers the others with 409' do
      # Makes every request start its lookup of the active loan at the same moment, so that only the row
      # lock can stop the extra requests from closing the loan a second time.
      lookup = /\ASELECT "loans"\.\* FROM "loans".*"returned_at" IS NULL/
      responses = line_up_at_sql(lookup, requests: 3, at: :start) do
        Array.new(3) { request_in_thread(:post, "/books/#{book.id}/returns") }.map(&:value)
      end

      expect(responses.map(&:status)).to contain_exactly(201, 409, 409)
      first_return = JSON.parse(responses.find { |response| response.status == 201 }.body)['returned_at']
      expect(loan.reload.returned_at.utc.iso8601(3)).to eq(first_return)
    end
  end
end
