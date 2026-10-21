# Exceptions app: renders errors raised outside the controllers (unknown routes, malformed
# request bodies, crashes) in the same format as ErrorHandling.
class ErrorsController < ApplicationController
  def show
    exception = request.env["action_dispatch.exception"]
    status = ActionDispatch::ExceptionWrapper.status_code_for_exception(exception.class.name)

    render_error status, Rack::Utils::SYMBOL_TO_STATUS_CODE.key(status).to_s, Rack::Utils::HTTP_STATUS_CODES[status]
  end
end
