class ReadersController < ApplicationController
  def create
    reader = Reader.new(reader_params)
    reader.save!

    render json: ReaderResource.new(reader).serialize, status: :created
  rescue ActiveRecord::RecordNotUnique
    # A concurrent request took the card number or email after the uniqueness validation passed.
    # Validating again reports it as an ordinary validation error.
    reader.validate!
    raise
  end

  private

  def reader_params
    params.permit(:card_number, :name, :email)
  end
end
