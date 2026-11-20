# Middleware

`Lucid::Tenancy::Middleware` finds the tenant of each request, runs the app in its schema and puts the schema back at the end. The Railtie inserts it before `ActionDispatch::Cookies`.

```ruby
Lucid::Tenancy.configure do |config|
  config.base_domain = "example.com"
  config.shared_paths = ["/up", "/admin"]
end
```

A request to `alfa.example.com` runs in the tenant `alfa`.

## Resolving the tenant

By default the identifier is the part of the host before `base_domain`. `example.com` itself, hosts outside the base domain and an empty `base_domain` give no identifier, and the request runs in the shared schema.

`ignored_identifiers` lists identifiers that mean "no tenant". Whatever the default rule or a resolver returns, a match (case-insensitive) runs the request in the shared schema.

```ruby
config.ignored_identifiers = ["www"]
```

With `strict_base_domain = true` and a `base_domain`, a host that is neither the base domain nor one of its subdomains resolves to no tenant, and neither the subdomain rule nor a custom resolver is consulted.

A resolver replaces that rule. It receives the Rack request and returns an identifier or `nil`.

```ruby
config.resolver = ->(request) { request.get_header("HTTP_X_TENANT") }
```

The identifier is looked up in the tenant model. A request with an identifier but no tenant is answered by `on_missing_tenant`, a Rack app that returns 404 by default.

```ruby
config.on_missing_tenant = ->(env) { [302, { "location" => "/landing" }, []] }
```

## Shared paths

Paths in `shared_paths` run without a tenant. A prefix matches on a path boundary: `/up` matches `/up` and `/up/x`, but not `/update` or `/upload`.

## Proxies

`X-Forwarded-Host` is ignored unless the request comes from a proxy in `trusted_proxies`. Without it the host the client connected to is used.

```ruby
config.trusted_proxies = ["10.0.0.0/8", "127.0.0.1"]
```

Entries are IP addresses or CIDR ranges, matched against `REMOTE_ADDR`.

## Cleanup

The schema goes back to shared when the response body is closed, so streamed responses keep their tenant while they stream. If the app raises, the schema is reset and the error goes up.
