class LoanHistoryResource
  include Alba::Resource

  attributes :borrowed_at, :due_on, :returned_at
  one :reader, resource: ReaderResource
end
