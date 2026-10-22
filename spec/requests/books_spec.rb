require 'rails_helper'

RSpec.describe 'Books', type: :request do
  describe 'GET /books' do
    def count_queries(&)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
      count
    end

    context 'when the library has no books' do
      it 'responds with 200 and an empty array' do
        get '/books'

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([])
      end
    end

    context 'with an available book' do
      it 'shows it as available without a current loan' do
        book = create(:book, serial_number: '000123', title: 'Clean Code', author: 'Robert C. Martin')

        get '/books'

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([
          {
            'id' => book.id,
            'serial_number' => '000123',
            'title' => 'Clean Code',
            'author' => 'Robert C. Martin',
            'status' => 'available',
            'current_loan' => nil
          }
        ])
      end

      it 'does not show the history of returned loans' do
        book = create(:book)
        create(:loan, :returned, book:)

        get '/books'

        expect(response.parsed_body.first).to include('status' => 'available', 'current_loan' => nil)
      end
    end

    context 'with a borrowed book' do
      let(:reader) { create(:reader, card_number: '000456', name: 'Ann Kowalska', email: 'ann@example.com') }
      let!(:book) { create(:book, serial_number: '000123', title: 'Clean Code', author: 'Robert C. Martin') }

      it 'shows it as borrowed, by whom and since when' do
        create(:loan, book:, reader:, borrowed_at: Time.zone.local(2026, 10, 21, 12, 30))

        travel_to(Time.zone.local(2026, 10, 22, 8)) { get '/books' }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([
          {
            'id' => book.id,
            'serial_number' => '000123',
            'title' => 'Clean Code',
            'author' => 'Robert C. Martin',
            'status' => 'borrowed',
            'current_loan' => {
              'borrowed_at' => '2026-10-21T12:30:00.000Z',
              'due_on' => '2026-11-20',
              'overdue' => false,
              'reader' => { 'card_number' => '000456', 'name' => 'Ann Kowalska', 'email' => 'ann@example.com' }
            }
          }
        ])
      end

      it 'shows only the active loan when the book was borrowed before' do
        create(:loan, :returned, book:, borrowed_at: Time.zone.local(2026, 9, 1))
        create(:loan, book:, reader:, borrowed_at: Time.zone.local(2026, 10, 21, 12, 30))

        get '/books'

        expect(response.parsed_body.first['current_loan']).to include('borrowed_at' => '2026-10-21T12:30:00.000Z')
      end

      it 'flags the loan as overdue once its due date has passed' do
        create(:loan, book:, reader:, borrowed_at: Time.zone.local(2026, 10, 1, 12))

        travel_to(Time.zone.local(2026, 11, 1)) { get '/books' }

        expect(response.parsed_body.first.dig('current_loan', 'overdue')).to be(true)
      end
    end

    context 'with several books' do
      it 'orders them by serial number' do
        create(:book, serial_number: '000300')
        create(:book, serial_number: '000100')
        create(:book, serial_number: '000200')
        create(:book, serial_number: '100000')

        get '/books'

        expect(response.parsed_body.map { |book| book['serial_number'] }).to eq(%w[000100 000200 000300 100000])
      end

      it 'reports the status of each book separately' do
        available = create(:book, serial_number: '000100')
        borrowed = create(:book, serial_number: '000200')
        create(:loan, book: borrowed)

        get '/books'

        expect(response.parsed_body.to_h { |book| [ book['id'], book['status'] ] })
          .to eq(available.id => 'available', borrowed.id => 'borrowed')
      end

      it 'takes the same number of queries however many books there are' do
        create(:loan)
        get '/books'
        queries_for_one_book = count_queries { get '/books' }

        create_list(:loan, 5)
        create_list(:loan, 3, :returned)
        create_list(:book, 4)
        queries_for_many_books = count_queries { get '/books' }

        expect(response.parsed_body.size).to eq(13)
        expect(queries_for_many_books).to eq(queries_for_one_book)
      end
    end
  end

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
          'author' => 'Andrew Hunt',
          'status' => 'available',
          'current_loan' => nil
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
