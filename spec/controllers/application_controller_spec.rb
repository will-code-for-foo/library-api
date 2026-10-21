require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  controller do
    def index
      head :ok
    end
  end

  def error_body(code:, message:, details: {})
    { 'error' => { 'code' => code, 'message' => message, 'details' => details } }
  end

  context 'when the record is not found' do
    before { allow(controller).to receive(:index).and_raise(ActiveRecord::RecordNotFound, 'Book not found') }

    it 'responds with 404 not_found' do
      get :index

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq(error_body(code: 'not_found', message: 'Book not found'))
    end
  end

  context 'when the record is invalid' do
    let(:widget) do
      stub_const('Widget', Class.new do
        include ActiveModel::Model

        attr_accessor :name, :code

        validates :name, presence: true
        validates :code, length: { minimum: 3 }
      end)
      Widget.new(code: 'a').tap(&:validate)
    end

    before { allow(controller).to receive(:index).and_raise(ActiveRecord::RecordInvalid.new(widget)) }

    it 'responds with 422 validation_failed and the messages of each attribute' do
      get :index

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to include(
        'code' => 'validation_failed',
        'details' => {
          'name' => [ "can't be blank" ],
          'code' => [ 'is too short (minimum is 3 characters)' ]
        }
      )
    end
  end

  context 'when a request parameter is missing' do
    before { allow(controller).to receive(:index).and_raise(ActionController::ParameterMissing.new(:card_number)) }

    it 'responds with 400 parameter_missing' do
      get :index

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to include('code' => 'parameter_missing')
      expect(response.parsed_body['error']['message']).to include('card_number')
    end
  end

  context 'when a business rule conflicts' do
    before { allow(controller).to receive(:index).and_raise(ConflictError, 'Book is already borrowed') }

    it 'responds with 409 conflict' do
      get :index

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq(error_body(code: 'conflict', message: 'Book is already borrowed'))
    end
  end
end
