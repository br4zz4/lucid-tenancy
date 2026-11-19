module Lucid
  module Tenancy
    # Low level schema helpers shared by provisioning and migrations. Internal.
    module Schema
      module_function

      def connection
        ActiveRecord::Base.lease_connection
      end

      def exists?(schema)
        connection.select_value("SELECT 1 FROM information_schema.schemata WHERE schema_name = #{connection.quote(schema)}").present?
      end

      def create(schema)
        connection.execute("CREATE SCHEMA #{connection.quote_schema_name(schema)}")
      end

      def drop(schema)
        connection.execute("DROP SCHEMA #{connection.quote_schema_name(schema)} CASCADE")
      end

      def tables(schema)
        connection.select_values(
          "SELECT table_name FROM information_schema.tables WHERE table_schema = #{connection.quote(schema)} ORDER BY table_name"
        )
      end

      # Makes sure +schema+ has its own +schema_migrations+ and +ar_internal_metadata+, so a
      # migration is recorded in the schema it ran in and never in the shared one.
      def ensure_migration_tables(schema)
        quoted = connection.quote_schema_name(schema)
        connection.execute("CREATE TABLE IF NOT EXISTS #{quoted}.schema_migrations (version character varying NOT NULL PRIMARY KEY)")
        connection.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS #{quoted}.ar_internal_metadata (
            key character varying NOT NULL PRIMARY KEY,
            value character varying,
            created_at timestamp(6) without time zone NOT NULL,
            updated_at timestamp(6) without time zone NOT NULL
          )
        SQL
      end

      # Runs the block with +schema+ (then the shared schema) as search_path and restores the previous one.
      def with_path(schema)
        previous = connection.schema_search_path
        shared = connection.quote_schema_name(Lucid::Tenancy.configuration.shared_schema)
        connection.lucid_tenancy_apply("#{connection.quote_schema_name(schema)}, #{shared}")
        yield
      ensure
        connection.lucid_tenancy_apply(previous)
      end
      # Like +with_path+ but without the shared schema, so a dump sees only +schema+.
      def with_only_path(schema)
        previous = connection.schema_search_path
        connection.lucid_tenancy_apply(connection.quote_schema_name(schema))
        yield
      ensure
        connection.lucid_tenancy_apply(previous)
      end
    end
  end
end
