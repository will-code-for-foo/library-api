class BookResource
  include Alba::Resource

  attributes :id, :serial_number, :title, :author, :status
  one :active_loan, key: :current_loan, resource: CurrentLoanResource
end
