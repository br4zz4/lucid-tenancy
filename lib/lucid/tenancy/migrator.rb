module Lucid
  module Tenancy
    # Runs migrations where they belong: +tenancy :shared+ once in the shared schema,
    # +tenancy :tenant+ in the template and in every tenant, each schema keeping its own
    # +schema_migrations+. Nothing is ever dropped or recreated.
    class Migrator
      # A migration context that only sees the migrations of one mode.
      class ScopedContext < ActiveRecord::MigrationContext
        def initialize(paths, mode, *rest)
          @tenancy_mode = mode
          super(paths, *rest)
        end

        def migrations
          super.select { |proxy| Migrator.mode_of(proxy) == @tenancy_mode }
        end
      end

      class << self
        # @return [Symbol] the declared tenancy of a migration
        # @raise [Error::MissingTenancyDeclaration] the migration did not declare it
        def mode_of(proxy)
          mode = proxy.send(:migration).class.tenancy_mode
          return mode if mode

          raise Error::MissingTenancyDeclaration,
                "#{proxy.filename} must declare `tenancy :tenant` or `tenancy :shared`"
        end

        # Migrates the shared schema, the template and every tenant.
        def migrate(paths: default_paths, version: nil)
          each_scope(paths) { |context| context.migrate(version) }
        end

        # Rolls back +steps+ migrations in every schema.
        def rollback(steps: 1, paths: default_paths)
          each_scope(paths) { |context| context.rollback(steps) }
        end

        # @return [Hash{String => Array<Integer>}] pending versions per schema
        def pending(paths: default_paths)
          result = {}
          each_scope(paths, name: true) do |context, schema|
            done = context.get_all_versions
            result[schema] = context.migrations.map(&:version).reject { |version| done.include?(version) }
          end
          result
        end

        def default_paths
          ActiveRecord::Base.connection_pool.migrations_paths
        end

        private

        def each_scope(paths, name: false)
          pool = ActiveRecord::Base.connection_pool
          shared = Lucid::Tenancy.configuration.shared_schema
          Schema.with_path(shared) { yield context(paths, :shared, pool), shared }

          Template.create! unless name
          schemas = []
          schemas << Template.schema if Template.exists?
          schemas.concat(Lucid::Tenancy.map { |tenant| tenant.schema_name }) if tenancy_model?
          schemas.each do |schema|
            Schema.ensure_migration_tables(schema)
            Schema.with_path(schema) { yield context(paths, :tenant, pool), schema }
          end
        end

        def tenancy_model?
          Lucid::Tenancy.tenant_class
          true
        rescue Error::TenantNotFound
          false
        end

        def context(paths, mode, pool)
          ScopedContext.new(paths, mode, ActiveRecord::SchemaMigration.new(pool), ActiveRecord::InternalMetadata.new(pool))
        end
      end
    end
  end
end
