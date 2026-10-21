# Raised when a request breaks a business rule, e.g. borrowing a book that is already borrowed.
class ConflictError < StandardError
end
