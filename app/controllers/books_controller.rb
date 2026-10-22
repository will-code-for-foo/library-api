class BooksController < ApplicationController
  def index
    books = Book.with_current_loan.order(:serial_number)

    render json: BookResource.new(books).serialize
  end

  def show
    book = Book.with_current_loan.with_loan_history.find(params[:id])

    render json: BookDetailResource.new(book).serialize
  end

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
