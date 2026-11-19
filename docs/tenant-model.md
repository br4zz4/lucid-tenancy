# Tenant model

The tenant model represents one customer: a school, an account, a company. It lives in the shared schema and names the schema of each tenant.

```ruby
class Organization < ApplicationRecord
  include Lucid::Tenancy::Tenant
  tenant_identifier :subdomain
end
```

The concern does four things. It makes the model `tenancy :shared`, validates the identifier, adds `schema_name`, and adds `provision` and `drop`.

## Declaring the model by configuration

```ruby
Lucid::Tenancy.configure do |config|
  config.tenant_model = "Organization"
  config.tenant_identifier = :subdomain
end
```

`tenant_model` is a string and is resolved lazily, so it survives code reloading. The gem includes the concern into that class on first use, so the `include` line is optional.

Both forms can be used together as long as they agree. If `config.tenant_model` names one class and a different class includes the concern, or two classes include it, the gem raises `Lucid::Tenancy::Error::ConfigurationConflict`. The same happens when `tenant_identifier :other` in the model disagrees with an explicit `config.tenant_identifier`.

## The identifier

`tenant_identifier` is the attribute that identifies the tenant. It defaults to `config.tenant_identifier`, which defaults to `:subdomain`. Its value becomes the schema name:

- it is stripped, lowercased, and hyphens become underscores (`"Escola-Alfa"` becomes `escola_alfa`)
- the result must match `[a-z][a-z0-9_]{1,62}`
- it cannot be `public`, `information_schema`, anything starting with `pg_`, the template schema, the shared schema, or a name in `config.reserved_identifiers`

An invalid identifier is a validation error on the model, so `Organization.create!(subdomain: "public")` raises `ActiveRecord::RecordInvalid`. The identifier also cannot change once the record exists, because the schema is named after it.

```ruby
Organization.new(subdomain: "Escola-Alfa").schema_name   # => "escola_alfa"
Organization.new(subdomain: "pg_catalog").schema_name    # raises Lucid::Tenancy::Error::ReservedIdentifier
```

`schema_name` raises `InvalidIdentifier` or `ReservedIdentifier` instead of returning a bad name. The gem always quotes schema names when it builds SQL.

## Provision and drop

```ruby
organization.provision
organization.drop
```

These are shortcuts for `Lucid::Tenancy.provision(organization)` and `Lucid::Tenancy.drop(organization)`. See [Provisioning](provisioning.md).

## Finding a tenant

`with(tenant:)` and `set(tenant:)` accept a tenant or its identifier. An identifier is looked up with `find_by(tenant_identifier => identifier.to_s)` and raises `Lucid::Tenancy::Error::TenantNotFound` if nothing matches.
