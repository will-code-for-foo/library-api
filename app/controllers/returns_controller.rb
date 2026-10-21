class ReturnsController < ApplicationController
  def create
    book = Book.find(params[:book_id])

    loan = book.return!

    render json: LoanResource.new(loan).serialize, status: :created
  end
end
