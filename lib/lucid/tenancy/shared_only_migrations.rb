module Lucid
  module Tenancy
    # Rails' own pending-migration checks (+maintain_test_schema!+, +check_all_pending!+) look
    # only at the shared schema, so they must only see +tenancy :shared+ migrations. The
    # tenant ones are tracked per schema by Lucid::Tenancy::Migrator.
    module SharedOnlyMigrations
      def migrations
        all = super
        return all if is_a?(Migrator::ScopedContext) || !primary_pool?

        all.select { |proxy| Migrator.mode_of(proxy) == :shared }
      end

      private

      def primary_pool?
        pool = connection_pool
        pool.nil? || pool.db_config.name == Lucid::Tenancy.primary_db_name
      end
    end
  end
end
