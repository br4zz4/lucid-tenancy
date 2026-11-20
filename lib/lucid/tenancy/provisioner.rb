module Lucid
  module Tenancy
    # Creates and drops tenant schemas.
    #
    # A schema is created by loading the template dump (+db/tenant_schema.rb+) inside a
    # transaction, so a failed provisioning leaves nothing behind.
    module Provisioner
      module_function

      def provision(tenant)
        schema = tenant.schema_name
        raise Error::AlreadyProvisioned, "schema #{schema.inspect} already exists" if Schema.exists?(schema)

        dump = Lucid::Tenancy.configuration.tenant_schema_path
        raise Error::TenantNotFound, "template dump not found at #{dump}" unless File.exist?(dump)

        Schema.connection.transaction(requires_new: true) do
          Schema.create(schema)
          Schema.ensure_migration_tables(schema)
          Schema.with_path(schema) do
            load_dump(dump)
            Migrator.register_dumped_versions
          end
        end

        hook = Lucid::Tenancy.configuration.after_provision
        Lucid::Tenancy.with(tenant: tenant) { hook.call(tenant) } if hook
        tenant
      end

      def drop(tenant)
        Schema.drop(tenant.schema_name)
        tenant
      end

      def load_dump(path)
        previous = ActiveRecord::Migration.verbose
        ActiveRecord::Migration.verbose = false
        load(path)
      ensure
        ActiveRecord::Migration.verbose = previous
      end
    end
  end
end
