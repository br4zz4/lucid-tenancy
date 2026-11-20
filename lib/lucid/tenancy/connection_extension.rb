module Lucid
  module Tenancy
    # Mixed into the PostgreSQL adapter: applies the search_path of the current tenant to a
    # connection and takes it back to the shared schema when the connection returns to the pool,
    # so a tenant never leaks to the next user of the same connection.
    module ConnectionExtension
      # @api private
      def lucid_tenancy_apply(search_path)
        @lucid_tenancy_applied = true
        self.schema_search_path = search_path
      end

      # @api private
      def lucid_tenancy_reset
        return unless @lucid_tenancy_applied

        @lucid_tenancy_applied = false
        self.schema_search_path = quote_schema_name(Lucid::Tenancy.configuration.shared_schema)
      end

      # @api private
      def lucid_tenancy_checkout
        return unless lucid_tenancy_primary?

        tenant = Lucid::Tenancy::State.tenant
        lucid_tenancy_apply(Lucid::Tenancy.search_path_for(tenant, self)) if tenant
      end

      # @api private
      def lucid_tenancy_primary?
        owner = pool
        owner.nil? || owner.db_config.name == ActiveRecord::Base.connection_pool.db_config.name
      end

      private

      def configure_connection
        super
        lucid_tenancy_checkout
      end
    end
  end
end
