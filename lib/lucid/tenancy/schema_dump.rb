module Lucid
  module Tenancy
    # Writes and checks +db/tenant_schema.rb+, the dump of the template schema that
    # provisioning loads for every new tenant.
    module SchemaDump
      module_function

      # Writes the dump of the template schema to +path+.
      def write(path = Lucid::Tenancy.configuration.tenant_schema_path)
        File.open(path, "w") { |file| file.write(dump) }
        path
      end

      # @return [String] the Ruby schema of the template
      def dump
        io = StringIO.new
        Schema.with_only_path(Template.schema) do
          ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)
        end
        io.string.lines.reject { |line| line.match?(/\A\s*(create_schema|enable_extension)\b/) }.join.gsub(", force: :cascade", "")
      end

      # @return [Boolean] whether the file on disk matches the template schema
      def in_sync?(path = Lucid::Tenancy.configuration.tenant_schema_path)
        File.exist?(path) && File.read(path) == dump
      end
    end
  end
end
