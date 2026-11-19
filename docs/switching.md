# Switching tenants

Switching changes the PostgreSQL `search_path` of the current connection. The tenant schema comes first and the shared schema second, so tenant tables win and shared tables are still reachable.

## with

```ruby
Lucid::Tenancy.with(tenant: alfa) { Student.count }
Lucid::Tenancy.with(tenant: "beta") { Student.count }
```

The tenant is a record or its identifier. The block runs in that schema and returns its own value. The previous schema is restored when the block ends, including when it raises. `with` without a block raises `ArgumentError`.

Blocks nest. The inner block restores the outer tenant, not the shared schema.

## shared

```ruby
Lucid::Tenancy.shared { Organization.count }
```

The block runs with only the shared schema on the path. Tenant tables are not found there. `with(tenant: nil)` is the same thing.

## set

```ruby
Lucid::Tenancy.set(tenant: alfa)
Student.count
Lucid::Tenancy.set(tenant: nil)
```

`set` switches until the next `set`. It returns the new tenant. Use it in consoles, scripts and the middleware. In application code prefer `with`, which cannot forget to switch back. `set(tenant: x) { }` with a block behaves like `with`.

## current

```ruby
Lucid::Tenancy.current         # => #<Organization subdomain: "alfa"> or nil
Lucid::Tenancy.current_scope   # => :tenant or :shared
```

`current` is the tenant record, or `nil` in the shared schema. The state is per thread and per fiber.

## Enumerable

`Lucid::Tenancy` is Enumerable over the tenants. The block of each element runs inside that tenant.

```ruby
Lucid::Tenancy.each { |tenant| Student.count }
Lucid::Tenancy.map { |tenant| [tenant.subdomain, Student.count] }.to_h
Lucid::Tenancy.find { |tenant| Student.exists?(name: "Ana") }
```

The previous schema is restored afterwards. `count`, `size` and `to_a` read the tenant list from the shared schema and do not switch.

## Shared and tenant tables

```ruby
class Plan < ApplicationRecord
  tenancy :shared
end
```

`tenancy :shared` sets the table name to `public.plans` (the shared schema from `config.shared_schema`), so the model reads the same table whatever the current tenant is. The default is `tenancy :tenant`. `tenancy` with any other value raises `ArgumentError`. `Plan.shared_table?` and `Plan.tenant_table?` tell them apart.

## Connections

When a connection goes back to the pool, its `search_path` is reset to the shared schema, and when one is checked out inside a tenant, the path is applied again. A tenant never leaks to the next user of a connection.
