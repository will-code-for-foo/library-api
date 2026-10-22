class BookDetailResource < BookResource
  many :loan_history, key: :loans, resource: LoanHistoryResource
end
