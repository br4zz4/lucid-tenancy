# Roadmap

## SQL dump

Provisioning loads `db/tenant_schema.rb`, a Rails Ruby dump. It does not represent triggers, functions or views. A `structure.sql` based dump, written from the template schema, would cover them for apps that need it.

## Out of scope

The gem will not support other databases, and it will not add other isolation strategies such as a `tenant_id` column or a database per tenant. One strategy keeps the gem small and its guarantees checkable. See [Decisions](decisions.md).
