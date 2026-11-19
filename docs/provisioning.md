# Provisioning

Provisioning creates the schema of a new tenant.

```ruby
organization = Organization.create!(subdomain: "gama")
Lucid::Tenancy.provision(organization)
```

`organization.provision` does the same. It returns the tenant.

## How it works

The gem checks that the schema does not exist, then creates it and loads `db/tenant_schema.rb` into it, all inside one transaction. If anything fails, the schema is not created. The path of the dump is `config.tenant_schema_path` and defaults to `db/tenant_schema.rb`. The dump also records the migration versions, so the new schema starts with the right `schema_migrations`.

Provisioning an existing schema raises `Lucid::Tenancy::Error::AlreadyProvisioned`. A missing dump file raises `Lucid::Tenancy::Error::TenantNotFound` with the path.

Because the schema comes from a dump of the template, foreign keys, indexes and sequences belong to the new schema and not to the template.

## Initial data

```ruby
Lucid::Tenancy.configure do |config|
  config.after_provision = ->(tenant) { Role.create!(name: "admin") }
end
```

The hook runs after the transaction commits, inside the new tenant, so models read and write its tables. It receives the tenant.

## Dropping

```ruby
organization.drop
```

This runs `DROP SCHEMA ... CASCADE` and deletes everything in the tenant. It does not delete the tenant record.

## What the dump does not represent

The dump is Rails `schema.rb` format. It covers tables, columns, indexes, foreign keys and the like. It does not represent triggers, functions or views, so a tenant provisioned from the dump will not have them. Apps that need them have to wait for the SQL dump on the [roadmap](roadmap.md). `create_schema` and `enable_extension` lines are removed from the dump, so extensions must exist in the database beforehand.

## Cost

Provisioning loads the whole schema, so its time grows with the number of tables. It runs inside the request or job that calls it. For apps that create tenants from a web form, call it from a job.

The template schema (`config.template_schema`, default `tenancy_template`) is internal. It is migrated with the tenants, and `migrate` creates it the first time and fills it with the `tenancy :tenant` migrations, then writes `db/tenant_schema.rb` from it.
