require "rack"

module Lucid
  module Tenancy
    # Rack middleware: resolves the tenant of the request, runs the app in its schema and
    # always goes back to the shared schema, even for streamed bodies.
    #
    # Paths in +config.shared_paths+ run without a tenant. A host that names a tenant
    # that does not exist is answered by +config.on_missing_tenant+. A host with no tenant
    # at all runs in the shared schema.
    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        config = Lucid::Tenancy.configuration
        return @app.call(env) if shared_path?(env["PATH_INFO"], config.shared_paths)

        request = Rack::Request.new(env)
        identifier = Resolver.identifier(request)
        return @app.call(env) if identifier.blank?

        tenant = Lucid::Tenancy.tenant_class.find_by_tenancy_identifier(identifier)
        return config.on_missing_tenant.call(env) unless tenant

        Lucid::Tenancy.set(tenant: tenant)
        status, headers, body = @app.call(env)
        [status, headers, Rack::BodyProxy.new(body) { Lucid::Tenancy.set(tenant: nil) }]
      rescue StandardError
        Lucid::Tenancy.set(tenant: nil)
        raise
      end

      private

      def shared_path?(path, prefixes)
        prefixes.any? { |prefix| path == prefix || path.start_with?("#{prefix.chomp('/')}/") }
      end
    end
  end
end
