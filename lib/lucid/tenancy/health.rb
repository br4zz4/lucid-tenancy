module Lucid
  module Tenancy
    # How far the schema of a tenant is from the template: missing and extra tables, columns that
    # differ and migrations still to run. Built from the catalog only, never from row data.
    class Health < Data.define(:schema, :provisioned, :missing_tables, :extra_tables, :column_drift, :pending_versions)
      ColumnDrift = Data.define(:table, :column, :expected, :actual)

      IGNORED_TABLES = %w[schema_migrations ar_internal_metadata].freeze

      class << self
        # @param schema [String] schema of the tenant
        # @return [Health]
        def inspect_schema(schema, paths:)
          return unhealthy(schema) unless Schema.exists?(schema)

          template = columns_of(Template.schema)
          actual = columns_of(schema)
          new(
            schema: schema,
            provisioned: true,
            missing_tables: (template.keys - actual.keys).sort,
            extra_tables: (actual.keys - template.keys).sort,
            column_drift: drift(template, actual),
            pending_versions: Migrator.pending(paths: paths, schema: schema)
          )
        end

        private

        def unhealthy(schema)
          new(schema: schema, provisioned: false, missing_tables: [], extra_tables: [], column_drift: [], pending_versions: [])
        end

        def drift(template, actual)
          (template.keys & actual.keys).sort.flat_map do |table|
            (template[table].keys | actual[table].keys).sort.filter_map do |column|
              expected = template[table][column]
              found = actual[table][column]
              ColumnDrift.new(table: table, column: column, expected: expected, actual: found) unless expected == found
            end
          end
        end

        def columns_of(schema)
          connection = Schema.connection
          rows = connection.select_rows(<<~SQL)
            SELECT c.table_name, c.column_name, c.data_type
            FROM information_schema.columns c
            JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
            WHERE c.table_schema = #{connection.quote(schema)} AND t.table_type = 'BASE TABLE'
              AND c.table_name NOT IN (#{IGNORED_TABLES.map { |name| connection.quote(name) }.join(', ')})
          SQL
          tables = Schema.tables(schema).reject { |name| IGNORED_TABLES.include?(name) }.to_h { |name| [name, {}] }
          rows.each { |table, column, type| (tables[table] ||= {})[column] = type }
          tables
        end
      end

      def provisioned? = provisioned

      def ok?
        provisioned && missing_tables.empty? && extra_tables.empty? && column_drift.empty? && pending_versions.empty?
      end
    end
  end
end
