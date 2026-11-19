require "active_support"
require "active_support/core_ext"
require "active_support/isolated_execution_state"
require "active_record"

require "lucid/tenancy/version"
require "lucid/tenancy/errors"
require "lucid/tenancy/configuration"
require "lucid/tenancy/state"
require "lucid/tenancy/identifier"
require "lucid/tenancy/model"
require "lucid/tenancy/connection_extension"

module Lucid
  # Multi-tenancy on PostgreSQL: one schema per tenant, inside the same database.
  #
  # @example
  #   Lucid::Tenancy.with(tenant: school) { Student.count }
  #   Lucid::Tenancy.shared { Organization.count }
  module Tenancy
    class << self
      # @return [Lucid::Tenancy::Configuration]
      def configuration
        @configuration ||= Configuration.new
      end

      # Yields the global configuration.
      #
      # @yieldparam config [Lucid::Tenancy::Configuration]
      def configure
        yield configuration
        configuration
      end

      # Restores the default configuration.
      def reset_configuration!
        @configuration = Configuration.new
      end

      # Runs the block in the schema of +tenant+ and restores the previous schema afterwards, even on error.
      #
      # @param tenant [#schema_name, String, Symbol, nil] the tenant, or +nil+ for the shared schema
      # @return the value of the block
      def with(tenant:)
        raise ArgumentError, "with needs a block" unless block_given?

        previous = State.tenant
        activate(resolve(tenant))
        yield
      ensure
        activate(previous) if defined?(previous)
      end

      # Runs the block in the shared schema.
      def shared(&block)
        with(tenant: nil, &block)
      end

      # Switches to +tenant+ until the next +set+. With a block it behaves like +with+.
      #
      # @param tenant [#schema_name, String, Symbol, nil] +nil+ goes back to the shared schema
      def set(tenant:, &block)
        return with(tenant: tenant, &block) if block

        activate(resolve(tenant))
        State.tenant
      end

      # @return [Object, nil] the current tenant, or +nil+ in the shared schema
      def current
        State.tenant
      end

      # @return [Symbol] +:tenant+ or +:shared+
      def current_scope
        State.tenant ? :tenant : :shared
      end

      # @api private
      def search_path_for(tenant, connection)
        shared_schema = connection.quote_schema_name(configuration.shared_schema)
        return shared_schema unless tenant

        "#{connection.quote_schema_name(tenant.schema_name)}, #{shared_schema}"
      end

      private

      def resolve(tenant)
        return nil if tenant.nil?
        return tenant if tenant.respond_to?(:schema_name)

        tenant_class = configuration.tenant_model&.then { |name| name.constantize }
        raise Error::TenantNotFound, "no tenant model configured to resolve #{tenant.inspect}" unless tenant_class

        tenant_class.find_by_tenancy_identifier(tenant) ||
          raise(Error::TenantNotFound, "no tenant #{tenant.inspect}")
      end

      def activate(tenant)
        State.tenant = tenant
        connection = ActiveRecord::Base.lease_connection
        connection.lucid_tenancy_apply(search_path_for(tenant, connection))
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  include Lucid::Tenancy::Model

  ActiveRecord::Base.class_eval do
    def self.find_by_tenancy_identifier(identifier)
      find_by(Lucid::Tenancy.configuration.tenant_identifier => identifier.to_s)
    end
  end
end

ActiveSupport.on_load(:active_record_postgresqladapter) do
  include Lucid::Tenancy::ConnectionExtension
  set_callback :checkin, :before, :lucid_tenancy_reset
  set_callback :checkout, :after, :lucid_tenancy_checkout
end
