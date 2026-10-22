# Demo data for trying every endpoint right after `docker compose up`: a handful of books and readers, one book borrowed.
# It can run any number of times: books and readers are looked up by serial number and card number, and the loan is
# created only for a book that was never borrowed, so a book returned through the API stays returned.

books = [
  [ "000001", "Clean Code", "Robert C. Martin" ],
  [ "000002", "The Pragmatic Programmer", "Andrew Hunt, David Thomas" ],
  [ "000003", "Refactoring", "Martin Fowler" ],
  [ "000004", "Domain-Driven Design", "Eric Evans" ],
  [ "000005", "Designing Data-Intensive Applications", "Martin Kleppmann" ]
].map do |serial_number, title, author|
  Book.find_or_create_by!(serial_number:) { |book| book.assign_attributes(title:, author:) }
end

readers = [
  [ "000101", "Ann Kowalska", "ann.kowalska@example.com" ],
  [ "000102", "Jan Nowak", "jan.nowak@example.com" ],
  [ "000103", "Maria Wiśniewska", "maria.wisniewska@example.com" ]
].map do |card_number, name, email|
  Reader.find_or_create_by!(card_number:) { |reader| reader.assign_attributes(name:, email:) }
end

borrowed_book = books.first
borrowed_book.borrow!(readers.first) unless borrowed_book.loans.exists?
