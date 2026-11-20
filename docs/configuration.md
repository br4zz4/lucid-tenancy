# Configuration

`bin/rails g lucid:tenancy:install` creates `config/initializers/lucid_tenancy.rb`. Every option is on `Lucid::Tenancy.configure`:

```ruby
Lucid::Tenancy.configure do |config|
  config.tenant_model = "Organization"
  config.tenant_identifier = :subdomain
  config.base_domain = "example.com"
  config.shared_paths = ["/up"]
  config.trusted_proxies = ["10.0.0.0/8"]
  config.after_provision = ->(tenant) { Role.create!(name: "admin") }
end
```

| Option | Default | Meaning |
| --- | --- | --- |
| `tenant_model` | `nil` | Name of the tenant model, as a string. Not needed if the model includes `Lucid::Tenancy::Tenant`. |
| `tenant_identifier` | `:subdomain` | Attribute of the tenant model that names the tenant and its schema. |
| `shared_schema` | `"public"` | Schema holding the shared tables. |
| `template_schema` | `"tenancy_template"` | Internal schema that new tenants are built from. |
| `tenant_schema_path` | `db/tenant_schema.rb` | Dump loaded by `provision` and written by `lucid:tenancy:dump`. |
| `after_provision` | `nil` | Callable run with the tenant, inside its schema, after provisioning. |
| `base_domain` | `nil` | Domain whose subdomains are tenants. |
| `ignored_identifiers` | `[]` | Identifiers the resolver treats as "no tenant", e.g. `["www"]`. |
| `strict_base_domain` | `false` | With `base_domain` set, a host outside it resolves to no tenant, even with a custom `resolver`. |
| `resolver` | `nil` | Callable `request -> identifier`. Replaces the subdomain rule. |
| `shared_paths` | `[]` | Path prefixes served without a tenant, matched on a path boundary. |
| `on_missing_tenant` | 404 Rack app | Rack app answering when the host names an unknown tenant. |
| `trusted_proxies` | `[]` | Proxies whose `X-Forwarded-Host` is trusted. |
| `reserved_identifiers` | `[]` | Strings or regexps that can never be a tenant, besides `public`, `information_schema`, `pg_*`, the template and the shared schema. |

`Lucid::Tenancy.reset_configuration!` restores the defaults. It exists for tests.
