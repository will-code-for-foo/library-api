class BooksController < ApplicationController
  def create
    book = Book.create!(book_params)

    render json: BookResource.new(book).serialize, status: :created
  end

  private

  def book_params
    params.permit(:serial_number, :title, :author)
  end
end
