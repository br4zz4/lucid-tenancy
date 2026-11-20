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

        # Rolls back the last +steps+ migrations, counted over all migrations in version order, each
        # one in the schemas it belongs to.
        def rollback(steps: 1, paths: default_paths)
          applied = {}
          each_scope(paths, name: true) do |context, schema|
            known = context.migrations.map(&:version)
            context.get_all_versions.each { |version| (applied[version] ||= []) << schema if known.include?(version) }
          end
          applied.keys.sort.last(steps).reverse_each do |version|
            each_scope(paths) { |context, schema| context.run(:down, version) if applied[version].include?(schema) }
          end
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

        # Records in the current schema every +tenancy :tenant+ migration up to the version of the
        # dump that was just loaded. Rails' own +assume_migrated_upto_version+ only sees the
        # +tenancy :shared+ migrations (see SharedOnlyMigrations), so it would leave the tenant ones out.
        def register_dumped_versions(paths: default_paths)
          scoped = context(paths, :tenant, ActiveRecord::Base.connection_pool)
          done = scoped.get_all_versions
          dumped = done.max
          return unless dumped

          scoped.migrations.map(&:version).each do |version|
            scoped.schema_migration.create_version(version) if version <= dumped && !done.include?(version)
          end
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
          schemas.concat(Lucid::Tenancy.map { |tenant| tenant.schema_name }.select { |schema| Schema.exists?(schema) }) if tenancy_model?
          schemas.each do |schema|
            ensure_tables(schema) unless name
            Schema.with_path(schema) { yield context(paths, :tenant, pool), schema }
          end
        end

        def ensure_tables(schema)
          return Schema.ensure_migration_tables(schema) if schema == Template.schema
          return if Schema.migration_tables?(schema)

          raise Error::MissingMigrationTable,
                "schema #{schema.inspect} has no schema_migrations; run `rake lucid:tenancy:baseline[#{schema}]` to mark it as in sync with the template"
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
