# Lucid::Tenancy

Multi-tenancy for Rails on PostgreSQL. Every tenant gets its own schema in the same database, and the gem switches between them for requests, jobs, consoles and migrations.

```ruby
class Organization < ApplicationRecord
  include Lucid::Tenancy::Tenant
  tenant_identifier :subdomain
end

class Student < ApplicationRecord
end

class PlanCatalog < ApplicationRecord
  tenancy :shared
end

class WelcomeJob < ApplicationJob
  def perform(student)
    WelcomeMailer.with(student: student).hello.deliver_now
  end
end

Lucid::Tenancy.with(tenant: "alfa") do
  student = Student.create!(name: "Ana")
  WelcomeJob.perform_later(student)
  Student.count
end

Lucid::Tenancy.each { |tenant| puts "#{tenant.subdomain}: #{Student.count}" }
```

Inside `with`, `Student` reads and writes `alfa.students`. The job is enqueued with the tenant and runs in `alfa` on the worker. `PlanCatalog` is `tenancy :shared`, so it always reads `public.plan_catalogs`, whatever the current tenant is. When the block ends, the schema goes back to what it was, even if the block raised.

## Installation

```ruby
gem 'lucid-tenancy', github: 'br4zz4/lucid-tenancy', tag: 'v0.1.1'
```

Ruby 3.2 or newer, Rails 7.2 or newer, PostgreSQL. Then:

```sh
bundle install
bin/rails g lucid:tenancy:install
```

The generator creates `config/initializers/lucid_tenancy.rb` with every option and its default.

## What you get

The middleware reads the subdomain of each request, finds the tenant and runs the request in its schema. Models are tenant models unless they say `tenancy :shared`. Migrations must say which one they are, and `db:migrate` runs them in the shared schema once and in every tenant schema. `Lucid::Tenancy.provision(tenant)` creates the schema of a new tenant from a dump, inside a transaction.

Tenant identifiers become schema names, so they are validated, always quoted, and names like `public` or `pg_catalog` are refused.

## Guides

- [Getting started](docs/getting-started.md)
- [Tenant model](docs/tenant-model.md)
- [Switching tenants](docs/switching.md)
- [Migrations](docs/migrations.md)
- [Provisioning](docs/provisioning.md)
- [Middleware](docs/middleware.md)
- [Jobs and Action Cable](docs/jobs.md)
- [Testing](docs/testing.md)
- [Configuration](docs/configuration.md)
- [Errors](docs/errors.md)
- [Decisions](docs/decisions.md)
- [Migrating from Hotel](docs/migrating-from-hotel.md)
- [Roadmap](docs/roadmap.md)

## License

MIT. See [LICENSE](LICENSE).
