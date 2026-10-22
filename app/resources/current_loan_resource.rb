class CurrentLoanResource
  include Alba::Resource

  attributes :borrowed_at, :due_on
  attribute(:overdue) { |loan| loan.overdue? }
  one :reader, resource: ReaderResource
end
