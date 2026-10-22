# Library API – TODO

Work through the list top to bottom, one feature at a time. Tick an item when every acceptance criterion under it is ticked, its specs pass and `bin/ci` is green. Every item comes with specs covering its criteria.

## API overview

| Method   | Path                      | Item |
|----------|---------------------------|------|
| `POST`   | `/books`                  | 4    |
| `POST`   | `/readers`                | 5    |
| `POST`   | `/books/:book_id/loans`   | 6    |
| `POST`   | `/books/:book_id/returns` | 7    |
| `GET`    | `/books`                  | 8    |
| `GET`    | `/books/:id`              | 9    |
| `DELETE` | `/books/:id`              | 10   |

Books are addressed by their `id` in paths. Readers are identified by library card number in the request body. Serial numbers and card numbers are strings, so leading zeros are kept.

## Task 1: Foundation

- [x] Rails 8.1.4 API-only app on Ruby 4.0.7 with PostgreSQL
- [x] RSpec, FactoryBot, shoulda-matchers, Alba and Solid Queue in the Gemfile
- [x] `Dockerfile` and `docker-compose.yml` with `db`, `web` and `worker` services
- [x] Solid Queue tables in the primary database

- [x] **1. Test setup**
  - Context: every following item is delivered with specs, so the test tooling has to work out of the box.
  - Acceptance criteria:
    - [x] Specs can use FactoryBot factories directly and the shoulda-matchers one-liners
    - [x] `bundle exec rspec` runs against PostgreSQL and exits 0

- [x] **2. CI runs the specs**
  - Context: CI currently runs only security scans and the linter.
  - Acceptance criteria:
    - [x] The CI workflow runs the specs against PostgreSQL
    - [x] `bin/ci` runs the specs too
    - [x] A pull request shows the spec job passing next to the existing jobs

- [x] **3. JSON responses and error handling**
  - Context: all endpoints serialize with Alba and report errors the same way, so API clients handle one error format.
  - Acceptance criteria:
    - [x] Every error response has the shape `{ "error": { "code": "...", "message": "...", "details": { } } }`
    - [x] Record not found → 404 `not_found`
    - [x] Validation failure → 422 `validation_failed`, with `details` mapping each attribute to its messages
    - [x] Missing request parameter → 400 `parameter_missing`
    - [x] Business rule conflict (for example borrowing a borrowed book) → 409 `conflict`

## Task 2: Books, readers and loans

- [x] **4. Add a new book** — `POST /books`
  - Context: staff add books to the catalogue. A book has a six-digit serial number, a title and an author.
  - Acceptance criteria:
    - [x] `serial_number` is required and is exactly six digits (`"000123"` is valid; `"12345"`, `"1234567"` and `"12345a"` are not)
    - [x] `serial_number` is unique, also guaranteed at the database level
    - [x] `title` and `author` are required and may not be blank
    - [x] `POST /books` with `serial_number`, `title` and `author` returns 201 and the book as `{ id, serial_number, title, author }`
    - [x] Missing fields, a malformed serial number and a duplicate serial number return 422 with per-attribute `details`

- [x] **5. Register a reader** — `POST /readers`
  - Context: staff need a way to create readers, otherwise nothing can be borrowed through the API. A reader has a six-digit library card number, a name and an email.
  - Acceptance criteria:
    - [x] `card_number` is required, exactly six digits and unique, also guaranteed at the database level
    - [x] `name` is required
    - [x] `email` is required, has a valid format and is unique ignoring case and surrounding whitespace (`Ann@Example.com` and `ann@example.com` collide)
    - [x] `POST /readers` returns 201 and `{ card_number, name, email }`
    - [x] Invalid input and duplicates return 422 with per-attribute `details`

- [x] **6. Borrow a book** — `POST /books/:book_id/loans` with `{ "card_number": "123456" }`
  - Context: borrowing creates a loan, which links a book to a reader. Each book is borrowed for 30 days, and a book can be out with only one reader at a time.
  - Acceptance criteria:
    - [x] A loan stores the book, the reader, when it was borrowed and the due date, which is 30 days after the borrow date
    - [x] A book can have only one active (not returned) loan, also guaranteed at the database level
    - [x] A successful borrow returns 201 and `{ book: { id, serial_number }, reader: { card_number, name, email }, borrowed_at, due_on, returned_at: null }`
    - [x] Borrowing an already borrowed book returns 409 `conflict` and creates no loan
    - [x] An unknown book or card number returns 404; a missing `card_number` returns 400
    - [x] Two concurrent borrow requests for the same book produce exactly one loan and one 409

- [x] **7. Return a book** — `POST /books/:book_id/returns`
  - Context: a return closes the book's active loan and makes the book available again. The closed loan stays as history.
  - Acceptance criteria:
    - [x] Returning a borrowed book sets the return time and returns 201 with the closed loan, in the same shape as the borrow response
    - [x] The book is available afterwards and can be borrowed again, creating a new loan and keeping the old one
    - [x] Returning a book that is not borrowed returns 409 `conflict`, including a second return of the same loan
    - [x] An unknown book returns 404

- [x] **8. List all books with availability** — `GET /books`
  - Context: staff see at a glance which books are available and which are borrowed, by whom and since when.
  - Acceptance criteria:
    - [x] Returns 200 with an array of `{ id, serial_number, title, author, status, current_loan }`
    - [x] `status` is `"available"` or `"borrowed"`
    - [x] For an available book `current_loan` is `null`; for a borrowed book it is `{ borrowed_at, due_on, overdue, reader: { card_number, name, email } }`
    - [x] `overdue` is `true` only when the loan is active and `due_on` is before today (additional logic: it lets staff spot late books)
    - [x] Books are ordered by `serial_number`
    - [x] An empty library returns `[]`
    - [x] The number of SQL queries does not grow with the number of books
    - [x] The response of `POST /books` includes the new fields as well

- [x] **9. Show a book with its borrowing history** — `GET /books/:id`
  - Context: staff look up one book together with every time it was borrowed and by whom.
  - Acceptance criteria:
    - [x] Returns 200 with the book fields of item 8 plus `loans`
    - [x] `loans` lists every loan, newest first, as `{ borrowed_at, due_on, returned_at, reader: { card_number, name, email } }`
    - [x] The active loan is included with `returned_at: null`
    - [x] A book that was never borrowed has `loans: []`
    - [x] An unknown book id returns 404
    - [x] The number of SQL queries does not grow with the number of loans

- [x] **10. Delete a book** — `DELETE /books/:id`
  - Context: staff remove books that left the library. A book that is currently borrowed must not disappear from under its reader.
  - Acceptance criteria:
    - [x] Deleting an available book returns 204 and the book no longer appears in `GET /books`
    - [x] The loan history of a deleted book is deleted with it
    - [x] Deleting a borrowed book returns 409 `conflict` and the book and its loan are unchanged
    - [x] An unknown book id returns 404

## Task 3: Email reminders

- [ ] **11. Reminder emails**
  - Context: readers get two emails about a loan, 3 days before the due date and on the due date. Emails are never really sent: the payload is logged and previews are available.
  - Acceptance criteria:
    - [ ] The 3-days-before email is addressed to the reader, its subject names the book title and due date, and its body says the book is due in 3 days and includes reader name, title, author, serial number and due date
    - [ ] The due-date email has the same fields and says the book is due today
    - [ ] Both emails have a library sender address
    - [ ] Previews of both emails are viewable in development
    - [ ] When an email is delivered, nothing leaves the app and the payload (from, to, subject, body) is written to the log at INFO level

- [ ] **12. Reminder scheduling**
  - Context: once a day the app finds the loans that need a reminder and emails their readers. Running the job twice on the same day must not send duplicates.
  - Acceptance criteria:
    - [ ] A job runs automatically once a day (production and development) as a Solid Queue recurring task
    - [ ] For a loan borrowed on day D, the reader gets one 3-days-before email on D+27 and one due-date email on D+30, and nothing on other days
    - [ ] Each reminder is sent at most once per loan, even when the job runs several times a day
    - [ ] A loan returned before the reminder date gets no email
    - [ ] A reader with two loans due on the same day gets two emails
    - [ ] After `docker compose up` the `worker` service runs the recurring task and the email payloads show up in `docker compose logs worker`

## Task 4: Delivery

- [ ] **13. Seed data**
  - Context: a reviewer should be able to try every endpoint right after `docker compose up`.
  - Acceptance criteria:
    - [ ] Seeds create a handful of books and readers, with one book borrowed
    - [ ] Seeds can run repeatedly without creating duplicates
    - [ ] On a clean machine `docker compose up` loads the seed data

- [ ] **14. README**
  - Context: the README replaces the Rails default and tells a reviewer how to run the app and why it is built this way.
  - Acceptance criteria:
    - [ ] How to start the app with `docker compose up` and where it listens
    - [ ] A `curl` example for each endpoint in the overview
    - [ ] How to run the specs
    - [ ] Key design decisions, each with its reason
    - [ ] Additional logic beyond the staff operations in the overview, each with a one-line reason: reader registration, overdue flag, protection against double borrowing, reminder idempotency, email normalization
    - [ ] Ideas for improvement
    - [ ] Text only describes what the app does and uses

- [ ] **15. Final verification**
  - Context: the delivered repository must work on a clean machine.
  - Acceptance criteria:
    - [ ] `docker compose down -v && docker compose up --build` starts `db`, `web` and `worker` from scratch and `GET /up` returns 200
    - [ ] The flow create book → register reader → borrow → list → show → return → delete works through `curl` against the running containers
    - [ ] A loan back-dated by 27 days triggers a 3-days-before email visible in the `worker` logs
    - [ ] `bin/ci` and `bundle exec rspec` pass
