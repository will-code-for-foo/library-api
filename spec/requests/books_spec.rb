require 'rails_helper'

RSpec.describe 'Books', type: :request do
  describe 'POST /books' do
    let(:params) { { serial_number: '000123', title: 'The Pragmatic Programmer', author: 'Andrew Hunt' } }

    def error_details
      response.parsed_body.dig('error', 'details')
    end

    context 'with valid attributes' do
      it 'creates the book and responds with 201 and the book' do
        expect { post '/books', params:, as: :json }.to change(Book, :count).by(1)

        book = Book.last
        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to eq(
          'id' => book.id,
          'serial_number' => '000123',
          'title' => 'The Pragmatic Programmer',
          'author' => 'Andrew Hunt'
        )
      end

      it 'keeps the leading zeros of the serial number' do
        post '/books', params:, as: :json

        expect(Book.last.serial_number).to eq('000123')
      end

      it 'ignores attributes that are not part of the payload' do
        post '/books', params: params.merge(id: 999, created_at: 1.year.ago), as: :json

        expect(response.parsed_body['id']).not_to eq(999)
      end
    end

    context 'with missing fields' do
      it 'responds with 422 and the messages of every missing attribute' do
        expect { post '/books', params: {}, as: :json }.not_to change(Book, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']['code']).to eq('validation_failed')
        expect(error_details).to eq(
          'serial_number' => [ "can't be blank" ],
          'title' => [ "can't be blank" ],
          'author' => [ "can't be blank" ]
        )
      end

      it 'reports only the attributes that are missing' do
        post '/books', params: params.except(:title), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(error_details.keys).to eq([ 'title' ])
      end

      it 'treats blank title and author as missing' do
        post '/books', params: params.merge(title: ' ', author: ''), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(error_details.keys).to contain_exactly('title', 'author')
      end
    end

    context 'with a malformed serial number' do
      %w[12345 1234567 12345a].each do |serial_number|
        it "responds with 422 for #{serial_number.inspect}" do
          expect { post '/books', params: params.merge(serial_number:), as: :json }.not_to change(Book, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(error_details).to eq('serial_number' => [ 'must be exactly six digits' ])
        end
      end

      it 'responds with 422 for a too short serial number sent as a number' do
        post '/books', params: params.merge(serial_number: 123), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(error_details.keys).to eq([ 'serial_number' ])
      end
    end

    context 'with a duplicate serial number' do
      before { create(:book, serial_number: '000123') }

      it 'responds with 422 and creates no book' do
        expect { post '/books', params:, as: :json }.not_to change(Book, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(error_details).to eq('serial_number' => [ 'has already been taken' ])
      end
    end

    context 'when another request takes the serial number after the validations passed' do
      let(:book) { Book.new(params) }

      before do
        create(:book, serial_number: '000123')
        validations = 0
        allow(Book).to receive(:new).and_return(book)
        allow(book).to receive(:valid?).and_wrap_original do |valid, *args|
          (validations += 1) == 1 || valid.call(*args)
        end
      end

      it 'responds with 422 and creates no book' do
        expect { post '/books', params:, as: :json }.not_to change(Book, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']['code']).to eq('validation_failed')
        expect(error_details).to eq('serial_number' => [ 'has already been taken' ])
      end
    end
  end
end
