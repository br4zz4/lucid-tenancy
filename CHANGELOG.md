# Changelog

## 0.1.5

- Switching the `search_path` now clears the Active Record query cache, so the same SQL in another tenant is never answered from the previous tenant's cached result (requests, jobs and `rails runner` run with the query cache on).

## 0.1.4

- Fixed `ConnectionNotDefined` during `db:schema:dump`: the primary pool check no longer needs a connected `ActiveRecord::Base` (`Lucid::Tenancy.primary_db_name`).

## 0.1.3

- Action Cable runs each command inside `around_command`, so the tenant is restored even when the command raises and never leaks from a previous one.
- The PostgreSQL adapter reapplies the tenant `search_path` on `reconnect!`/`verify!`; the checkout callback only touches the primary pool, never cache or cable.
- `rollback` ignores versions in a schema that its migration context does not know (orphan versions no longer raise `UnknownMigrationVersionError`).
- `db:prepare` also runs the tenant-aware migrator (existing and new databases) and refreshes the tenant dump. `ActiveRecord::Migration.check_all_pending!` and `maintain_test_schema!` still see only the shared schema; use `lucid:tenancy:status` for tenants.
- `serialize` of an Active Job uses its origin tenant; the shared-only migration filter applies only to the primary database.
- `Lucid::Tenancy::ActionCable` and `Lucid::Tenancy::RSpec` are autoloaded.
- The middleware never raises while closing the body and skips a redundant `SET` when already in the shared schema.
- `baseline` also seeds a `schema_migrations` that exists but is empty.

## 0.1.2

- Provisioning records versions in the tenant schema; a tenant without `schema_migrations` must be baselined (`lucid:tenancy:baseline`); the middleware always clears the tenant; `rollback` counts steps over all migrations; Active Job `perform_now` keeps its origin tenant; `db:migrate:*` tasks are tenancy-aware.

## 0.1.1

- Migrations are recorded in the schema they ran in (each tenant and the template get their own `schema_migrations`); the rake tasks load the Rails config correctly.

## 0.1.0

- `Lucid::Tenancy.with(tenant:)`, `shared`, `set(tenant:)`, `current` and `current_scope`, backed by per-thread and per-fiber state and a `search_path` that is reset when a connection returns to the pool.
- Enumerable over tenants: `each`, `map`, `find`, with `count`, `size` and `to_a` that do not switch schema.
- `tenancy :shared | :tenant` on models, migrations and Active Job classes.
- `Lucid::Tenancy::Tenant` concern, `tenant_identifier`, `config.tenant_model`, identifier validation and reserved names.
- `Lucid::Tenancy.provision` and `drop`, loading `db/tenant_schema.rb` in a transaction, with the `after_provision` hook.
- Tenant-aware migrations: `db:migrate` and `db:rollback` run shared migrations once and tenant migrations in the template and every tenant. `lucid:tenancy:migrate`, `rollback`, `status`, `dump` and `check` tasks.
- Rack middleware with `base_domain`, `resolver`, `shared_paths`, `on_missing_tenant` and `trusted_proxies`.
- Active Job carries the tenant. `Lucid::Tenancy::ActionCable` identifies the tenant of a connection.
- `Lucid::Tenancy::Minitest` and `lucid/tenancy/rspec` test helpers.
- `rails g lucid:tenancy:install`.
- Errors under `Lucid::Tenancy::Error`.
