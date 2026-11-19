module Lucid
  module Tenancy
    # The schema new tenants are built from. Internal: it is migrated with the tenants and its
    # dump is what provisioning loads.
    module Template
      module_function

      def schema
        Lucid::Tenancy.configuration.template_schema
      end

      def exists?
        Schema.exists?(schema)
      end

      def create!
        Schema.create(schema) unless exists?
      end

      def within(&block)
        Schema.with_path(schema, &block)
      end
    end
  end
end
