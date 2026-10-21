class LoansController < ApplicationController
  def create
    card_number = params.expect(:card_number)
    book = Book.find(params[:book_id])
    reader = Reader.find_by!(card_number:)

    loan = book.borrow!(reader)

    render json: LoanResource.new(loan).serialize, status: :created
  end
end
