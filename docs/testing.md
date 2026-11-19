# Testing

Tests run against a real PostgreSQL. Provision the tenants your tests need, then pick one per test.

## Minitest

```ruby
class StudentTest < ActiveSupport::TestCase
  include Lucid::Tenancy::Minitest
  tenant "alfa"

  test "counts students of the tenant" do
    Student.create!(name: "Ana")

    assert_equal 1, Student.count
  end
end
```

`tenant "alfa"` sets the tenant before each test and goes back to the shared schema after it. The tenant must already exist. A test case without `tenant` runs in the shared schema. Inside a test you can still use `Lucid::Tenancy.with(tenant: "beta") { }`.

## RSpec

```ruby
require "lucid/tenancy/rspec"

RSpec.describe Student, tenant: "alfa" do
  it "counts students of the tenant" do
    Student.create!(name: "Ana")

    expect(Student.count).to eq(1)
  end
end
```

Tag an example or a group with `tenant:`. The example runs inside `Lucid::Tenancy.with(tenant: "alfa")`.

## Creating tenants for the suite

Provision the tenants once, before the suite, for example in `rails_helper.rb` or `test_helper.rb`:

```ruby
Organization.find_or_create_by!(subdomain: "alfa").tap do |tenant|
  tenant.provision unless Lucid::Tenancy::Schema.exists?(tenant.schema_name)
end
```
