# Library API

Rails 8.1.4 (API-only) + PostgreSQL + Solid Queue. Staff manage books and readers, lend and return books; readers get email reminders before the due date.

## Run

```bash
docker compose up   # db + web (http://localhost:3000) + worker; GET /up -> 200
```

`web` loads `db/seeds.rb` on every start (idempotent): books `000001`–`000005`, readers `000101`–`000103`, book `000001` borrowed by `000101`. `docker compose down -v` resets the data.

## API

Books are addressed by `id`, readers by `card_number` in the body. Serial and card numbers are strings (leading zeros kept). Times are UTC.

```bash
H='Content-Type: application/json'

# add a book -> 201 (the examples assume it gets id 6)
curl -X POST localhost:3000/books -H "$H" -d '{"serial_number":"000006","title":"The Mythical Man-Month","author":"Frederick P. Brooks Jr."}'

# register a reader -> 201
curl -X POST localhost:3000/readers -H "$H" -d '{"card_number":"000104","name":"Piotr Zieliński","email":"piotr@example.com"}'

# borrow (due in 30 days) -> 201
curl -X POST localhost:3000/books/6/loans -H "$H" -d '{"card_number":"000104"}'

# list with availability, current loan and overdue flag -> 200
curl localhost:3000/books

# show with full borrowing history -> 200
curl localhost:3000/books/6

# return -> 201
curl -X POST localhost:3000/books/6/returns

# delete (also deletes its history) -> 204
curl -X DELETE localhost:3000/books/6
```

Errors are always `{ "error": { "code", "message", "details" } }`: `parameter_missing` 400, `not_found` 404, `conflict` 409 (borrowing a borrowed book, returning a free one, deleting a borrowed one), `validation_failed` 422 (`details` maps attributes to messages).

## Emails

Reminders go out 3 days before the due date and on it. `SendLoanRemindersJob` runs daily at 8am in `worker` (`config/recurring.yml`). Emails are only logged (INFO): `docker compose logs worker`. Previews in development: `bin/rails server`, then <http://localhost:3000/rails/mailers/loan_mailer>.

Try it now:

```bash
docker compose exec web bin/rails runner 'Loan.active.first.update!(borrowed_at: 27.days.ago, due_on: Date.current + 3); SendLoanRemindersJob.perform_later'
docker compose logs worker
```

## Specs

Needs Ruby 4.0.7 and PostgreSQL (`DATABASE_URL` if not on the default connection).

```bash
bin/rails db:test:prepare && bundle exec rspec
bin/ci   # RuboCop, gem audit, Brakeman, specs
```

## Design decisions

- **Unique constraints in the database too** (serial, card number, `lower(email)`, one active loan per book): validations alone lose races.
- **Resourceful routes**: an operation with no standard action becomes its own resource in a namespace: `Books::LoansController` and `Books::ReturnsController` (`app/controllers/books/`) behind `POST /books/:book_id/loans` and `/returns`.
- **Domain logic stays in controllers and models**: it is small. If it grows, it moves to service objects; request specs then cover only the controller layer and service specs the business logic.
- **One error format with a stable `code`**: clients branch on the code, not the message.
- **Alba resources**: each response contract lives in one small class.
- **Constant query count for `GET /books` and `GET /books/:id`**: loans and readers are preloaded.
- **Returned loans stay as history**; borrowing again adds a new loan.
- **Borrowed books cannot be deleted**, available ones take their history with them: a book never disappears from under its reader.
- **`due_on` is a UTC date, 30 days after borrowing**: one unambiguous calendar day.
- **Solid Queue in the primary database**: nothing to run besides PostgreSQL.
- **Reminders marked on the loan** by a single conditional update: concurrent or repeated runs send each one once; a failed email is released and retried.
- **Custom mail delivery method that logs the email**: the payload is visible in every environment without a mail server.
- **One image for `web` and `worker`**; the `web` entrypoint prepares the database and `worker` waits for `web`: one command works from scratch.

## Additional logic

- **Reader registration**: otherwise nothing can be borrowed through the API.
- **Overdue flag**: staff spot late books at a glance.
- **Double-borrowing protection** (database-level): of two concurrent borrows exactly one wins, the other gets 409.
- **Reminder idempotency**: the daily job can run again without emailing anyone twice.
- **Email normalization**: `Ann@Example.com` and `ann@example.com` are one address (unique index on `lower(email)`), and surrounding whitespace is rejected: nobody registers twice by changing case.

## Ideas

- Staff authentication and authorization
- Pagination, search and filters for `GET /books`
- Reader endpoints (show with loans, update, delete)
- Loan extension and overdue reminders
- Library time zone for due dates and reminder time
- Real email delivery over SMTP
- Soft-deleting books to keep their history
- OpenAPI description
