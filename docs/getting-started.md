# Getting started

Add the gem and run the generator.

```ruby
gem 'lucid-tenancy', github: 'br4zz4/lucid-tenancy', tag: 'v0.1.1'
```

```sh
bundle install
bin/rails g lucid:tenancy:install
```

The app needs PostgreSQL. The generator writes `config/initializers/lucid_tenancy.rb`:

```ruby
Lucid::Tenancy.configure do |config|
  config.tenant_model = "Organization"
  config.tenant_identifier = :subdomain
  config.base_domain = "example.com"
  config.shared_paths = ["/up"]
end
```

## The tenant model

The tenant is a regular model that lives in the shared schema. Its identifier becomes the schema name.

```ruby
class Organization < ApplicationRecord
  include Lucid::Tenancy::Tenant
  tenant_identifier :subdomain
end
```

With `config.tenant_model = "Organization"` the gem includes the concern for you, so the `include` is optional. See [Tenant model](tenant-model.md).

## Models and migrations

Every model is a tenant model by default: its table exists once per tenant schema. A model whose table is global says so.

```ruby
class Plan < ApplicationRecord
  tenancy :shared
end
```

Every migration declares where it runs.

```ruby
class CreateStudents < ActiveRecord::Migration[8.1]
  tenancy :tenant

  def change
    create_table :students do |t|
      t.string :name
    end
  end
end
```

`bin/rails db:migrate` runs `tenancy :shared` migrations once in `public` and `tenancy :tenant` migrations in every tenant schema. It also rewrites `db/tenant_schema.rb`, the dump used to create new tenants. See [Migrations](migrations.md).

## Creating a tenant

```ruby
organization = Organization.create!(subdomain: "alfa")
organization.provision
```

`provision` creates the schema `alfa` from `db/tenant_schema.rb`. See [Provisioning](provisioning.md).

## Using a tenant

```ruby
Lucid::Tenancy.with(tenant: "alfa") { Student.create!(name: "Ana") }
```

In a web request the [middleware](middleware.md) does this from the host, so a request to `alfa.example.com` runs in `alfa`. Jobs enqueued inside a tenant run in that tenant ([Jobs](jobs.md)). See [Switching tenants](switching.md) for the rest of the API.
