# Renders every error as { "error": { "code": "...", "message": "...", "details": { } } }.
module ErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound do |error|
      # error.message may contain the SQL conditions of the lookup, so name only the model.
      render_error :not_found, "not_found", error.model ? "#{error.model} not found" : error.message
    end

    rescue_from ActiveRecord::RecordInvalid do |error|
      render_error :unprocessable_content, "validation_failed", error.message, error.record.errors.to_hash
    end

    rescue_from ActionController::ParameterMissing do |error|
      render_error :bad_request, "parameter_missing", error.message
    end

    rescue_from ConflictError do |error|
      render_error :conflict, "conflict", error.message
    end
  end

  private

  def render_error(status, code, message, details = {})
    render json: ErrorResource.new({ code:, message:, details: }).serialize, status:
  end
end
