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
      attr_accessor :tenant_identifier
      # @return [String] schema the tenants are built from (internal, not part of the public API)
      attr_accessor :template_schema
      # @return [String] schema holding the tables shared by every tenant
      attr_accessor :shared_schema
      # @return [Array<String, Regexp>] identifiers that can never be a tenant, besides the built-in ones
      attr_accessor :reserved_identifiers

      def initialize
        @tenant_model = nil
        @tenant_identifier = :subdomain
        @template_schema = "tenancy_template"
        @shared_schema = "public"
        @reserved_identifiers = []
      end
    end
  end
end
