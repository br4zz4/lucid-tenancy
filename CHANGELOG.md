# Changelog

## Unreleased

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
