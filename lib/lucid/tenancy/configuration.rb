module Lucid
  module Tenancy
    # Settings, normally written in +config/initializers/lucid_tenancy.rb+.
    #
    # @example
    #   Lucid::Tenancy.configure do |config|
    #     config.tenant_model = "Organization"
    #     config.tenant_identifier = :subdomain
    #   end
    class Configuration
      # @return [String, nil] name of the model that represents a tenant
      attr_accessor :tenant_model
      # @return [Symbol] attribute of the tenant model that identifies it
      attr_reader :tenant_identifier
      # @return [String] schema the tenants are built from (internal, not part of the public API)
      attr_accessor :template_schema
      # @return [String] schema holding the tables shared by every tenant
      attr_accessor :shared_schema
      # @return [Proc, nil] called with the tenant, inside its schema, after it is provisioned
      attr_accessor :after_provision
      # @return [String] path of the template dump loaded to create a tenant schema
      attr_writer :tenant_schema_path
      # @return [Array<String, Regexp>] identifiers that can never be a tenant, besides the built-in ones
      attr_accessor :reserved_identifiers

      def tenant_identifier=(attribute)
        @tenant_identifier_explicit = true
        @tenant_identifier = attribute.to_sym
      end

      # @api private
      def tenant_identifier_explicit?
        @tenant_identifier_explicit
      end

      def tenant_schema_path
        @tenant_schema_path || (defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root.join("db/tenant_schema.rb").to_s : "db/tenant_schema.rb")
      end

      def initialize
        @tenant_model = nil
        @tenant_identifier = :subdomain
        @template_schema = "tenancy_template"
        @shared_schema = "public"
        @reserved_identifiers = []
        @after_provision = nil
        @tenant_schema_path = nil
        @tenant_identifier_explicit = false
      end
    end
  end
end
