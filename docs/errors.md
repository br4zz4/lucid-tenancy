# Errors

Every error raised by the gem inherits from `Lucid::Tenancy::Error`, which is a `StandardError`.

| Error | Raised when |
| --- | --- |
| `Error::InvalidIdentifier` | The identifier does not become a valid schema name (`[a-z][a-z0-9_]{1,62}` after normalizing). |
| `Error::ReservedIdentifier` | The identifier is `public`, `information_schema`, `pg_*`, the template or shared schema, or in `reserved_identifiers`. |
| `Error::TenantNotFound` | No tenant matches an identifier, no tenant model is configured, or the template dump file is missing. |
| `Error::AlreadyProvisioned` | `provision` finds the schema already there. |
| `Error::MissingTenancyDeclaration` | A migration does not declare `tenancy :tenant` or `tenancy :shared`. |
| `Error::ConfigurationConflict` | The tenant model or its identifier is declared twice with different values. |

Passing a bad value to `tenancy`, or calling `with` without a block, raises `ArgumentError`.

On the tenant model, `InvalidIdentifier` and `ReservedIdentifier` also become validation errors on the identifier attribute, so `create!` raises `ActiveRecord::RecordInvalid`. Calling `schema_name` directly raises them.

```ruby
begin
  Lucid::Tenancy.with(tenant: "nope") { }
rescue Lucid::Tenancy::Error::TenantNotFound => error
  error.message   # => "no tenant \"nope\""
end
```
