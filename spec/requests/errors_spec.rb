require 'rails_helper'

RSpec.describe 'Errors', type: :request do
  describe 'unknown route' do
    it 'responds with 404 in the common error format' do
      get '/nope'

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq('application/json')
      expect(response.parsed_body).to eq(
        'error' => { 'code' => 'not_found', 'message' => 'Not Found', 'details' => {} }
      )
    end
  end

  describe 'errors raised outside the controllers' do
    def render_error_for(exception)
      env = Rack::MockRequest.env_for('/', 'action_dispatch.exception' => exception)
      response = Rack::MockResponse.new(*ErrorsController.action(:show).call(env))
      [ response.status, JSON.parse(response.body) ]
    end

    it 'renders a malformed request body as 400 bad_request' do
      status, body = render_error_for(ActionDispatch::Http::Parameters::ParseError.new('unexpected token'))

      expect(status).to eq(400)
      expect(body).to eq('error' => { 'code' => 'bad_request', 'message' => 'Bad Request', 'details' => {} })
    end

    it 'renders any other exception as 500 internal_server_error without leaking its message' do
      status, body = render_error_for(StandardError.new('secret detail'))

      expect(status).to eq(500)
      expect(body).to eq(
        'error' => { 'code' => 'internal_server_error', 'message' => 'Internal Server Error', 'details' => {} }
      )
    end
  end
end
