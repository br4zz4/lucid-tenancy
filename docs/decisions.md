# Decisions

## PostgreSQL only

The gem supports PostgreSQL and nothing else. Schemas and `search_path` are what make the design small. MySQL and SQLite apps cannot use the gem.

## One schema per tenant, always

Every tenant gets its own independent schema in the same database, and the gem switches `search_path` to reach it. This is a rule, not an option.

Reasons:

- Isolation holds by construction. A query in `alfa` cannot see the tables of `beta`, whatever the code does.
- There is no `tenant_id` column to forget. One missed scope in a column-based design leaks a customer's data.
- There is no connection pool per tenant. Serverless PostgreSQL scales to zero and limits connections, so hundreds of pools do not fit. Switching a schema on a connection costs one statement.
- A tenant can be dropped, restored or inspected as a unit.

## Rejected alternatives

A `tenant_id` column (the `acts_as_tenant` approach) depends on every query carrying the scope. A database per tenant needs one pool per tenant and turns every migration into an operation across a fleet. Offering several strategies behind one option makes the gem large and its guarantees hard to check, so it has one.

## Other decisions

- Tenant identifiers become schema names, so they are validated, always quoted, and reserved names are refused.
- New tenants are built by loading a Rails schema dump inside a transaction, so a failed provisioning leaves nothing behind. The dump has limits, described in [Provisioning](provisioning.md).
- A tenant migration really runs in every tenant schema, and each schema records its own `schema_migrations`.
- Migrations never drop or recreate a schema.
- Active Job carries the tenant, so a job runs in the schema it was enqueued from.
- The vocabulary is plain: `with`, `shared`, `set`, `current`, `each`, `tenancy`. The schema new tenants are built from is an internal template and not part of the API.
