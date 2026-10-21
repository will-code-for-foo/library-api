require 'rails_helper'

RSpec.describe 'Readers', type: :request do
  describe 'POST /readers' do
    let(:params) { { card_number: '000123', name: 'Ann Smith', email: 'ann@example.com' } }

    def error_details
      response.parsed_body.dig('error', 'details')
    end

    context 'with valid attributes' do
      it 'creates the reader and responds with 201 and the reader' do
        expect { post '/readers', params:, as: :json }.to change(Reader, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to eq(
          'card_number' => '000123',
          'name' => 'Ann Smith',
          'email' => 'ann@example.com'
        )
      end

      it 'keeps the leading zeros of the card number' do
        post '/readers', params:, as: :json

        expect(Reader.last.card_number).to eq('000123')
      end

      it 'returns the email as it was sent' do
        post '/readers', params: params.merge(email: 'Ann@Example.com'), as: :json

        expect(response).to have_http_status(:created)
        expect(response.parsed_body['email']).to eq('Ann@Example.com')
      end
    end

    context 'with missing fields' do
      it 'responds with 422 and the messages of every missing attribute' do
        expect { post '/readers', params: {}, as: :json }.not_to change(Reader, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']['code']).to eq('validation_failed')
        expect(error_details).to eq(
          'card_number' => [ "can't be blank" ],
          'name' => [ "can't be blank" ],
          'email' => [ "can't be blank" ]
        )
      end

      it 'reports only the attributes that are missing' do
        post '/readers', params: params.except(:name), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(error_details.keys).to eq([ 'name' ])
      end

      it 'treats blank values as missing' do
        post '/readers', params: params.merge(name: ' ', email: '  '), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(error_details).to eq('name' => [ "can't be blank" ], 'email' => [ "can't be blank" ])
      end
    end

    context 'with a malformed card number' do
      %w[12345 1234567 12345a].each do |card_number|
        it "responds with 422 for #{card_number.inspect}" do
          expect { post '/readers', params: params.merge(card_number:), as: :json }.not_to change(Reader, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(error_details).to eq('card_number' => [ 'must be exactly six digits' ])
        end
      end

      it 'responds with 422 for a too short card number sent as a number' do
        post '/readers', params: params.merge(card_number: 123), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(error_details.keys).to eq([ 'card_number' ])
      end
    end

    context 'with a malformed email' do
      [ 'ann', 'ann@', '@example.com', 'ann example@example.com', ' ann@example.com ' ].each do |email|
        it "responds with 422 for #{email.inspect}" do
          expect { post '/readers', params: params.merge(email:), as: :json }.not_to change(Reader, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(error_details).to eq('email' => [ 'is not a valid email address' ])
        end
      end
    end

    context 'with a duplicate card number' do
      before { create(:reader, card_number: '000123') }

      it 'responds with 422 and creates no reader' do
        expect { post '/readers', params:, as: :json }.not_to change(Reader, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(error_details).to eq('card_number' => [ 'has already been taken' ])
      end
    end

    context 'with a duplicate email' do
      before { create(:reader, email: 'ann@example.com') }

      [ 'ann@example.com', 'Ann@Example.com', 'ANN@EXAMPLE.COM' ].each do |email|
        it "responds with 422 and creates no reader for #{email.inspect}" do
          expect { post '/readers', params: params.merge(email:), as: :json }.not_to change(Reader, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(error_details).to eq('email' => [ 'has already been taken' ])
        end
      end

      it 'responds with 422 and creates no reader when surrounding whitespace is the only difference' do
        expect { post '/readers', params: params.merge(email: ' ann@example.com '), as: :json }.not_to change(Reader, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(error_details.keys).to eq([ 'email' ])
      end
    end

    context 'with a duplicate card number and a duplicate email' do
      before { create(:reader, card_number: '000123', email: 'ann@example.com') }

      it 'reports both attributes' do
        post '/readers', params:, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(error_details).to eq(
          'card_number' => [ 'has already been taken' ],
          'email' => [ 'has already been taken' ]
        )
      end
    end

    context 'when another request takes the card number or email after the validations passed' do
      let(:reader) { Reader.new(params) }

      before do
        create(:reader, card_number: '000123')
        validations = 0
        allow(Reader).to receive(:new).and_return(reader)
        allow(reader).to receive(:valid?).and_wrap_original do |valid, *args|
          (validations += 1) == 1 || valid.call(*args)
        end
      end

      it 'responds with 422 and creates no reader' do
        expect { post '/readers', params:, as: :json }.not_to change(Reader, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']['code']).to eq('validation_failed')
        expect(error_details).to eq('card_number' => [ 'has already been taken' ])
      end
    end
  end
end
