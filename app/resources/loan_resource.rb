class LoanResource
  include Alba::Resource

  one :book do
    attributes :id, :serial_number
  end
  one :reader, resource: ReaderResource

  attributes :borrowed_at, :due_on, :returned_at
end
