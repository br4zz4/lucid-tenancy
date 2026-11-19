# Jobs and Action Cable

## Active Job

Active Job carries the tenant. A job enqueued inside a tenant runs in that tenant on the worker.

```ruby
class WelcomeJob < ApplicationJob
  def perform(student)
    WelcomeMailer.with(student: student).hello.deliver_now
  end
end

Lucid::Tenancy.with(tenant: "alfa") { WelcomeJob.perform_later(student) }
```

On enqueue the job stores the identifier of the current tenant in its serialized data. On the worker it runs in `Lucid::Tenancy.with(tenant: identifier)` and the previous schema is restored afterwards. A job enqueued outside any tenant runs in the shared schema. If the tenant no longer exists when the job runs, it raises `Lucid::Tenancy::Error::TenantNotFound`.

A job that is not about a tenant declares it:

```ruby
class CleanupJob < ApplicationJob
  tenancy :shared
end
```

A `tenancy :shared` job does not store a tenant and always runs in the shared schema. The default is `tenancy :tenant`. Any other value raises `ArgumentError`.

The extension is included in `ActiveJob::Base` by the Railtie.

## Action Cable

```ruby
require "lucid/tenancy/action_cable"

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include Lucid::Tenancy::ActionCable
  end
end
```

On connect the tenant identifier is resolved from the request host with the same resolver as the middleware, and the connection is `identified_by :tenant_identifier`. Before each command the tenant is set, and after each command the schema goes back to shared.
