# Connection pooling

Tenants are isolated with `SET search_path` on the connection, which is **session state**.

| Setup | Works |
|---|---|
| Direct connection to Postgres | yes |
| PgBouncer, `session` pool mode | yes |
| PgBouncer, `transaction` pool mode (e.g. Neon's `-pooler` endpoint) | no |

In transaction mode a transaction can run on a different real connection than the one that received the `SET`. Queries then fail with `relation "..." does not exist`, or read and write another tenant's schema without any error.

The gem refuses to boot (outside development and test) when the primary database host contains `-pooler`: `Lucid::Tenancy::Error::PooledConnection`. Use the direct endpoint. `config.allow_pooled_connection = true` turns the check off, only for a pool that keeps session state.

Supporting transaction-mode pooling would need a different design: `SET LOCAL search_path` inside each transaction, a database role per tenant, or schema-qualified queries.
