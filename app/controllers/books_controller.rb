class BooksController < ApplicationController
  def create
    book = Book.new(book_params)
    book.save!

    render json: BookResource.new(book).serialize, status: :created
  rescue ActiveRecord::RecordNotUnique
    # A concurrent request took the serial number after the uniqueness validation passed.
    # Validating again reports it as an ordinary validation error.
    book.validate!
    raise
  end

  private

  def book_params
    params.permit(:serial_number, :title, :author)
  end
end
