# Changelog

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
