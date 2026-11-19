# Migrating from Hotel

Hotel is the tenancy code that lived in `lib/hotel*.rb` in earlier apps. Each piece has a direct equivalent.

| Hotel | Lucid::Tenancy |
| --- | --- |
| `Hotel.as_guest(x) { }` | `Lucid::Tenancy.with(tenant: x) { }` |
| `Hotel.at_lobby { }` | `Lucid::Tenancy.shared { }` |
| `Hotel.guests.each { \|g\| ... }` | `Lucid::Tenancy.each { \|tenant\| ... }` |
| `Hotel.checkin(x)` | `Lucid::Tenancy.set(tenant: x)` |
| `Hotel.checkout` | `Lucid::Tenancy.set(tenant: nil)` |
| `Hotel.current`, `Current.organization` | `Lucid::Tenancy.current` |
| `tenant :public` in a model | `tenancy :shared` |
| `in_staff do ... end` in a migration | `tenancy :tenant` on the class, body without the wrapper |
| `as_staff` | gone: code that is not about a tenant runs in `shared` |

## Models

```ruby
# before
class Organization < ApplicationRecord
  tenant :public
end

# after
class Organization < ApplicationRecord
  include Lucid::Tenancy::Tenant
  tenant_identifier :subdomain
end
```

A model that is global but is not the tenant model uses `tenancy :shared`.

## Migrations

```ruby
# before
class AddShiftToEnrollments < ActiveRecord::Migration[7.2]
  include TenantMigrationContext

  def change
    return unless table_exists?(:enrollments)

    in_staff { add_column :enrollments, :shift, :integer }
  end
end

# after
class AddShiftToEnrollments < ActiveRecord::Migration[7.2]
  tenancy :tenant

  def change
    add_column :enrollments, :shift, :integer
  end
end
```

The `table_exists?` guard goes away because a tenant migration no longer runs in `public`.

## Jobs

`Hotel.checkin(x) { }` ignored its block, so jobs ran in `public`. Replace it with `Lucid::Tenancy.with(tenant: x) { }`, or drop it: a job enqueued inside a tenant already runs there. Jobs that are not about a tenant get `tenancy :shared`.

## Differences

Identifiers are validated and quoted, and `public`, `pg_*` and the template are refused. `db:migrate` runs migrations in every tenant and never drops a schema. Path prefixes in `shared_paths` match on a path boundary, and `X-Forwarded-Host` needs `trusted_proxies`.
