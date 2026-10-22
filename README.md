# Library API

A JSON API for library staff to manage books, register readers, lend and take back books, and a daily job that emails readers a reminder before a book is due. Built with Ruby 4.0.7, Rails 8.1.4 (API-only) and PostgreSQL.

## Run it

```bash
docker compose up
```

The first start builds the image. Three services come up:

| Service  | What it does                                                                                  |
|----------|-----------------------------------------------------------------------------------------------|
| `db`     | PostgreSQL 17                                                                                 |
| `web`    | Prepares the database, loads the seed data and serves the API on <http://localhost:3000>      |
| `worker` | Solid Queue: runs the daily reminder job and writes the email payloads to its log             |

`GET http://localhost:3000/up` returns 200 once the app is ready.

### Seed data

`web` loads `db/seeds.rb` on every start, so there is something to try right away: five books (serial numbers `000001`–`000005`), three readers (card numbers `000101`–`000103`) and one borrowed book (`000001`, borrowed by `000101`). The seeds can run any number of times without creating duplicates, and a book that was returned stays returned.

To bring the data back to the seed state, run `docker compose down -v` before `docker compose up`.

## API

Books are addressed by their `id` in paths. Readers are identified by library card number in the request body. Serial numbers and card numbers are strings, so leading zeros are kept. All dates and times are in UTC, so `due_on` and `overdue` follow the UTC calendar day.

| Method   | Path                      | Purpose                                      |
|----------|---------------------------|----------------------------------------------|
| `POST`   | `/books`                  | Add a book                                   |
| `POST`   | `/readers`                | Register a reader                            |
| `POST`   | `/books/:book_id/loans`   | Borrow a book                                |
| `POST`   | `/books/:book_id/returns` | Return a book                                |
| `GET`    | `/books`                  | List all books with their availability       |
| `GET`    | `/books/:id`              | Show a book with its full borrowing history  |
| `DELETE` | `/books/:id`              | Delete a book                                |

Examples against the seed data. They run in this order: the book added first gets the id `6` used by the later requests (on a database that already served other requests, use the `id` from the response).

```bash
# Add a book -> 201 { id, serial_number, title, author, status, current_loan }
curl -i -X POST http://localhost:3000/books \
  -H 'Content-Type: application/json' \
  -d '{"serial_number":"000006","title":"The Mythical Man-Month","author":"Frederick P. Brooks Jr."}'

# Register a reader -> 201 { card_number, name, email }
curl -i -X POST http://localhost:3000/readers \
  -H 'Content-Type: application/json' \
  -d '{"card_number":"000104","name":"Piotr Zieliński","email":"piotr.zielinski@example.com"}'

# Borrow book 6 as reader 000104 -> 201 with the loan, due in 30 days
curl -i -X POST http://localhost:3000/books/6/loans \
  -H 'Content-Type: application/json' \
  -d '{"card_number":"000104"}'

# List all books with availability and who has them -> 200
curl -i http://localhost:3000/books

# Show book 6 with its borrowing history -> 200
curl -i http://localhost:3000/books/6

# Return book 6 -> 201 with the closed loan
curl -i -X POST http://localhost:3000/books/6/returns

# Delete book 6 and its history -> 204
curl -i -X DELETE http://localhost:3000/books/6
```

Every error has the same shape, so a client handles one format:

```json
{ "error": { "code": "validation_failed", "message": "...", "details": { "serial_number": ["must be exactly six digits"] } } }
```

| Status | `code`              | When                                                                      |
|--------|---------------------|---------------------------------------------------------------------------|
| 400    | `parameter_missing` | A required request parameter is missing (for example `card_number`)       |
| 404    | `not_found`         | The book or reader does not exist                                         |
| 409    | `conflict`          | Borrowing a borrowed book, returning a book that is not borrowed, deleting a borrowed book |
| 422    | `validation_failed` | Invalid or duplicate input; `details` maps each attribute to its messages |

## Email reminders

A reader gets an email 3 days before the due date and another on the due date. A Solid Queue recurring task (`config/recurring.yml`) runs `SendLoanRemindersJob` every day at 8am in the `worker` service. Each reminder is sent at most once per loan, and a loan that was returned gets none.

Emails are never really sent. The payload (from, to, subject, body) is written to the log at INFO level, so it shows up in:

```bash
docker compose logs worker
```

Previews of both emails are available in development. Start the app with `bin/rails server` and open <http://localhost:3000/rails/mailers/loan_mailer>.

To see a reminder without waiting for the daily run, back-date the borrowed book's loan by 27 days and enqueue the job; the `worker` picks it up:

```bash
docker compose exec web bin/rails runner \
  'Loan.active.first.update!(borrowed_at: 27.days.ago, due_on: Date.current + 3); SendLoanRemindersJob.perform_later'
docker compose logs worker
```

## Specs

The specs use RSpec, FactoryBot and shoulda-matchers and run against PostgreSQL. They need Ruby 4.0.7 and a reachable PostgreSQL server; set `DATABASE_URL` (for example `postgres://postgres:postgres@localhost:5432`) when the server is not reachable with the default connection settings.

```bash
bin/rails db:test:prepare
bundle exec rspec
```

`bin/ci` runs everything the CI workflow checks: setup, RuboCop, the gem audit, Brakeman and the specs.

## Design decisions

- **Rules that must never break are enforced by the database as well as the models.** Unique indexes back the uniqueness of serial numbers, card numbers and emails, and a partial unique index allows only one active loan per book. Reason: validations alone lose races between concurrent requests.
- **Borrowing and returning are resources, not custom actions.** `POST /books/:book_id/loans` and `POST /books/:book_id/returns` use the standard `create` action. Reason: every route stays resourceful and a loan or a return is a thing the API creates.
- **One error format with a stable `code`.** Reason: clients branch on the code and never parse messages.
- **Alba resource classes serialize every response.** Reason: the JSON contract of each endpoint is defined in one small class, apart from the models.
- **Listing and showing books use a constant number of SQL queries.** Active loans, history and readers are loaded together with the books. Reason: response time must not grow with the number of books or loans.
- **A returned loan stays as history.** Borrowing again creates a new loan. Reason: `GET /books/:id` shows every time a book was borrowed and by whom.
- **A borrowed book cannot be deleted; deleting an available book deletes its loan history.** Reason: a book must not disappear from under its reader, and history without a book has no use.
- **A loan stores its due date as a date, 30 days after the borrow date, in UTC.** Reason: the due date is a calendar day, and one time zone keeps `due_on` and `overdue` unambiguous.
- **Solid Queue keeps jobs in the primary PostgreSQL database.** Reason: the app needs no service besides the database it already uses.
- **Reminders are recorded on the loan.** Each reminder has a timestamp column that the job claims with a single conditional update before it emails. Reason: only one of any number of repeated or concurrent runs sends a given reminder, and a failed email is released so a later run retries it.
- **A custom Action Mailer delivery method logs the email instead of sending it.** Reason: the payload is visible in the logs of every environment without any mail server.
- **One image serves `web` and `worker`.** The entrypoint of `web` prepares the database and loads the seeds, and `worker` waits until `web` is healthy. Reason: `docker compose up` works from a clean machine in one command and the worker never starts before the schema exists.

## Additional logic

Beyond the staff operations in the overview:

- **Reader registration (`POST /readers`):** without it nothing can be borrowed through the API.
- **Overdue flag:** `current_loan.overdue` is `true` when the loan is active and its due date is before today, so staff spot late books at a glance.
- **Protection against double borrowing:** a book can be out with only one reader, guaranteed by the database, so of two concurrent borrow requests exactly one succeeds and the other gets a 409.
- **Reminder idempotency:** each reminder is sent at most once per loan, so the daily job can run again, or overlap with another run, without emailing a reader twice.
- **Email normalization:** emails are compared ignoring case, so `Ann@Example.com` and `ann@example.com` are the same reader (a unique index on `lower(email)` guarantees it), and an email with surrounding whitespace is rejected as invalid. Reason: one person cannot register twice by changing the letter case.

## Ideas for improvement

- Authentication and authorization for library staff.
- Pagination, search and filtering (by status, title, author) for `GET /books`.
- Reader endpoints: show a reader with their current and past loans, update, delete.
- Extending a loan, and a reminder for books that are already overdue.
- A library time zone setting, so that the due date and the reminder time follow the library's local day.
- Real email delivery through SMTP instead of the log.
- Soft deletion of books, so that the borrowing history survives a deletion.
- An OpenAPI description of the endpoints.
