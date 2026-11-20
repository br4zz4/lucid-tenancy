# Hosts and URLs

Both helpers read `config.base_domain` and never the host of the current request, so a forged `Host` header cannot leak into generated URLs.

## Allowed hosts

```ruby
# config/environments/production.rb
config.hosts = Lucid::Tenancy::Hosts.allowed
```

Returns `[".example.com"]`: the base domain and every subdomain. It raises `Lucid::Tenancy::Error::ConfigurationConflict` when `base_domain` is not set.

## URL options of a tenant

```ruby
class ApplicationController < ActionController::Base
  def default_url_options
    return {} unless Lucid::Tenancy.current

    Lucid::Tenancy::Hosts.url_options_for(Lucid::Tenancy.current, port: request.port)
  end
end
```

Returns `{ host: "alfa.example.com" }`, plus `port:` when it is not blank, 80 or 443. The tenant must respond to `tenant_identifier` (models including `Lucid::Tenancy::Tenant` do). Without `base_domain` it raises `ConfigurationConflict`.
