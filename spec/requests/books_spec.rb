require 'rails_helper'

RSpec.describe 'Books', type: :request do
  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  describe 'GET /books' do
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

  describe 'GET /books/:id' do
    let(:book) { create(:book, serial_number: '000123', title: 'Clean Code', author: 'Robert C. Martin') }
    let(:ann) { create(:reader, card_number: '000456', name: 'Ann Kowalska', email: 'ann@example.com') }
    let(:bob) { create(:reader, card_number: '000789', name: 'Bob Nowak', email: 'bob@example.com') }

    context 'when the book was never borrowed' do
      it 'responds with 200, the book fields and an empty history' do
        get "/books/#{book.id}"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(
          'id' => book.id,
          'serial_number' => '000123',
          'title' => 'Clean Code',
          'author' => 'Robert C. Martin',
          'status' => 'available',
          'current_loan' => nil,
          'loans' => []
        )
      end
    end

    context 'when the book was borrowed several times' do
      before do
        create(:loan, :returned, book:, reader: ann, borrowed_at: Time.zone.local(2026, 8, 1, 10))
        create(:loan, :returned, book:, reader: bob, borrowed_at: Time.zone.local(2026, 9, 5, 14, 30))
        create(:loan, book:, reader: ann, borrowed_at: Time.zone.local(2026, 10, 21, 12, 30))
      end

      it 'lists every loan with its reader, the active one included with returned_at null' do
        get "/books/#{book.id}"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['loans']).to eq([
          {
            'borrowed_at' => '2026-10-21T12:30:00.000Z',
            'due_on' => '2026-11-20',
            'returned_at' => nil,
            'reader' => { 'card_number' => '000456', 'name' => 'Ann Kowalska', 'email' => 'ann@example.com' }
          },
          {
            'borrowed_at' => '2026-09-05T14:30:00.000Z',
            'due_on' => '2026-10-05',
            'returned_at' => '2026-09-06T14:30:00.000Z',
            'reader' => { 'card_number' => '000789', 'name' => 'Bob Nowak', 'email' => 'bob@example.com' }
          },
          {
            'borrowed_at' => '2026-08-01T10:00:00.000Z',
            'due_on' => '2026-08-31',
            'returned_at' => '2026-08-02T10:00:00.000Z',
            'reader' => { 'card_number' => '000456', 'name' => 'Ann Kowalska', 'email' => 'ann@example.com' }
          }
        ])
      end

      it 'shows the status and the current loan like the list does' do
        get "/books/#{book.id}"

        expect(response.parsed_body).to include('status' => 'borrowed')
        expect(response.parsed_body['current_loan']).to include('borrowed_at' => '2026-10-21T12:30:00.000Z')
      end

      it 'does not list the loans of other books' do
        create(:loan)

        get "/books/#{book.id}"

        expect(response.parsed_body['loans'].size).to eq(3)
      end
    end

    context 'when the book was borrowed and returned' do
      it 'shows it as available with the returned loan in the history' do
        create(:loan, :returned, book:, reader: ann)

        get "/books/#{book.id}"

        expect(response.parsed_body).to include('status' => 'available', 'current_loan' => nil)
        expect(response.parsed_body['loans'].size).to eq(1)
        expect(response.parsed_body['loans'].first['returned_at']).to be_present
      end
    end

    context 'when the book does not exist' do
      it 'responds with 404' do
        get '/books/0'

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to include('code' => 'not_found', 'message' => 'Book not found')
      end

      it 'responds with 404 for an id that is not a number' do
        get '/books/abc'

        expect(response).to have_http_status(:not_found)
      end

      %w[abc .5].each do |suffix|
        it "responds with 404 instead of showing the book when #{suffix.inspect} follows its id" do
          get "/books/#{book.id}#{suffix}"

          expect(response).to have_http_status(:not_found)
          expect(response.parsed_body['error']['code']).to eq('not_found')
        end
      end
    end

    it 'takes the same number of queries however many loans the book has' do
      create(:loan, book:)
      create_list(:loan, 2, :returned, book:)
      get "/books/#{book.id}"
      queries_for_few_loans = count_queries { get "/books/#{book.id}" }

      create_list(:loan, 8, :returned, book:)
      queries_for_many_loans = count_queries { get "/books/#{book.id}" }

      expect(response.parsed_body['loans'].size).to eq(11)
      expect(queries_for_many_loans).to eq(queries_for_few_loans)
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

  describe 'DELETE /books/:id' do
    let!(:book) { create(:book, serial_number: '000123') }

    def error
      response.parsed_body['error']
    end

    context 'when the book is available' do
      it 'responds with 204 and no body, and the book is gone from the list' do
        delete "/books/#{book.id}"

        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty

        get '/books'
        expect(response.parsed_body).to eq([])
        get "/books/#{book.id}"
        expect(response).to have_http_status(:not_found)
      end

      it 'deletes the loan history of the book with it, but not the loans of other books' do
        create(:loan, :returned, book:, borrowed_at: Time.zone.local(2026, 8, 1))
        create(:loan, :returned, book:, borrowed_at: Time.zone.local(2026, 9, 1))
        other_book = create(:book)
        other_loan = create(:loan, book: other_book)

        expect { delete "/books/#{book.id}" }.to change(Loan, :count).by(-2)

        expect(response).to have_http_status(:no_content)
        expect(Loan.all).to contain_exactly(other_loan)
        expect(Book.all).to contain_exactly(other_book)
      end

      it 'deletes a book that was returned after being borrowed' do
        post "/books/#{book.id}/loans", params: { card_number: create(:reader).card_number }, as: :json
        post "/books/#{book.id}/returns", as: :json

        delete "/books/#{book.id}"

        expect(response).to have_http_status(:no_content)
        expect(Book.exists?(book.id)).to be(false)
        expect(Loan.count).to eq(0)
      end
    end

    context 'when the book is borrowed' do
      let!(:loan) { create(:loan, book:) }

      it 'responds with 409 conflict and leaves the book and its loan unchanged' do
        create(:loan, :returned, book:, borrowed_at: 3.days.ago)

        expect { delete "/books/#{book.id}" }.not_to change { [ Book.count, Loan.count ] }

        expect(response).to have_http_status(:conflict)
        expect(error).to include('code' => 'conflict', 'message' => 'Borrowed book cannot be deleted')
        expect(book.reload).to have_attributes(serial_number: '000123')
        expect(loan.reload.returned_at).to be_nil
      end

      it 'can be deleted once it is returned' do
        delete "/books/#{book.id}"
        expect(response).to have_http_status(:conflict)

        post "/books/#{book.id}/returns", as: :json
        delete "/books/#{book.id}"

        expect(response).to have_http_status(:no_content)
      end
    end

    context 'when the book does not exist' do
      it 'responds with 404' do
        delete '/books/0'

        expect(response).to have_http_status(:not_found)
        expect(error).to include('code' => 'not_found', 'message' => 'Book not found')
      end

      it 'responds with 404 and keeps the book when characters follow the id of an existing book' do
        delete "/books/#{book.id}abc"

        expect(response).to have_http_status(:not_found)
        expect(Book.exists?(book.id)).to be(true)
      end
    end
  end

  describe 'DELETE /books/:id racing with a borrow request' do
    self.use_transactional_tests = false

    let!(:book) { create(:book) }
    let!(:reader) { create(:reader) }

    after do
      Loan.delete_all
      Reader.delete_all
      Book.delete_all
    end

    # Holds the delete request for a moment right after it checked that the book is not borrowed, which gives
    # the borrow request time to try to create a loan before the book is deleted.
    def hold_delete_after_availability_check(started)
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        next unless Thread.current[:delete_request] && payload[:sql].start_with?('SELECT 1 AS one FROM "loans"')

        started << :checked
        sleep 0.5
      end
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it 'never leaves a borrowed book deleted: the borrow request fails, no loan is lost' do
      checked = Queue.new
      responses = hold_delete_after_availability_check(checked) do
        deleting = Thread.new do
          Thread.current[:delete_request] = true
          ActiveRecord::Base.connection_pool.with_connection do
            Rack::MockRequest.new(Rails.application).delete("/books/#{book.id}")
          end
        end
        expect(checked.pop(timeout: 5)).to eq(:checked)
        borrowing = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Rack::MockRequest.new(Rails.application).post(
              "/books/#{book.id}/loans",
              'CONTENT_TYPE' => 'application/json',
              input: { card_number: reader.card_number }.to_json
            )
          end
        end
        [ deleting.value, borrowing.value ]
      end

      expect(responses.map(&:status)).to eq([ 204, 404 ])
      expect(Book.count).to eq(0)
      expect(Loan.count).to eq(0)
    end
  end
end
