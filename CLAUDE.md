# Library API

A Rails API for library management (books, readers, loans, email reminders) backed by PostgreSQL. `docker compose up` must produce a working app on a clean machine.

## Conventions

- **Use Rails generators wherever possible** (`bin/rails g model`, `migration`, `controller`, `resource`, `scaffold_controller`, `job`, `mailer`, `rspec:*`, ...), then edit the generated files. Do not hand-write files a generator can produce (models, migrations, controllers, jobs, mailers, specs).
- Pass attributes, types and options to the generator (`title:string serial_number:string:uniq reader:references`) so the output needs minimal edits. Review generated migrations before running them.
- Write by hand only what no generator covers (service objects, serializers, config, Docker files).
- **Routes are resourceful**: define them with Rails `resources` and its standard actions (`index`, `show`, `create`, `update`, `destroy`). When an operation has no standard action, model it as its own resource inside a `namespace` or `module` (for example a `returns` resource nested under books) so the paths stay resourceful.

## Decisions

- Ruby 4.0.7, Rails 8.1.4 API-only (`rails new --api`), PostgreSQL.
- JSON serialization with Alba resource classes.
- Tests with RSpec, FactoryBot and shoulda-matchers.
- Background jobs with Solid Queue, stored in the primary database (migration `CreateSolidQueueTables`); recurring jobs are declared in `config/recurring.yml`.
- Emails are never really sent: log the payload and provide mailer previews.
