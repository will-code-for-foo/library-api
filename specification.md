# Recruitment Task: Ruby on Rails Developer

Implement a simple API for a library management system. The API will be used by library staff to track and update the status of books owned by the library.

## Data

### Books

The system tracks the following information about the books and their borrowings:

- book's unique serial number (six-digit number)
- book's title
- book's author
- information whether the book is currently borrowed, when it was borrowed and by whom

### Readers

Readers in the system are described by the following data:

- unique library card number (six-digit number)
- name
- email (unique address)

## Features

The API should allow a library employee to:

1. Add a new book
2. Delete a book
3. Retrieve a list of all books together with information whether a given book is currently available or borrowed
4. Retrieve information about a specific book together with the full history of its borrowings (borrow date, return date, reader's data)
5. Borrow/return the book

## Email reminders

Each book is borrowed for 30 days. Therefore, the reader should receive email reminders from the library:

- a reminder to return the book 3 days before the due date
- a reminder to return the book on the due date

## Notes

- For the purpose of this task, user authentication and authorization can be omitted.
- The system does not need to send real emails - logging the email payload or using a mailer preview is sufficient.
- If you think there is any additional logic that would improve the solution beyond what's described, feel free to include it and briefly explain why.

## Technical requirements

- The solution should be implemented in Ruby on Rails.
- It should be delivered together with a docker-compose script. Running the command `docker compose up` should result in a working application.
- Use PostgreSQL as the database.
- In all other aspects, you are free to choose your approach (e.g. gems, third-party tools, etc.).
