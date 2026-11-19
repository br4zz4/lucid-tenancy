module Lucid
  module Tenancy
    # Included in the model that represents a tenant (a school, an account...).
    #
    # The model lives in the shared schema, gets a validated schema name and knows how to
    # create and drop its own schema.
    #
    # @example
    #   class Organization < ApplicationRecord
    #     include Lucid::Tenancy::Tenant
    #     tenant_identifier :subdomain
    #   end
    module Tenant
      extend ActiveSupport::Concern

      included do
        Lucid::Tenancy.register_tenant_model(self)
        tenancy :shared
        validate :tenancy_identifier_must_be_valid
        validate :tenancy_identifier_must_not_change, on: :update
      end

      class_methods do
        # Declares (or returns) the attribute that identifies the tenant.
        def tenant_identifier(attribute = nil)
          if attribute
            Lucid::Tenancy.register_tenant_identifier(self, attribute.to_sym)
            @tenant_identifier = attribute.to_sym
          end
          @tenant_identifier || Lucid::Tenancy.configuration.tenant_identifier
        end

        # @api private
        def find_by_tenancy_identifier(identifier)
          find_by(tenant_identifier => identifier.to_s)
        end
      end

      # @return [String] the schema of this tenant
      # @raise [Error::InvalidIdentifier, Error::ReservedIdentifier]
      def schema_name
        Identifier.schema_for(self[self.class.tenant_identifier])
      end

      # Creates the schema of this tenant from the template dump.
      def provision
        Lucid::Tenancy.provision(self)
      end

      # Drops the schema of this tenant and everything in it.
      def drop
        Lucid::Tenancy.drop(self)
      end

      private

      def tenancy_identifier_must_be_valid
        Identifier.schema_for(self[self.class.tenant_identifier])
      rescue Error::InvalidIdentifier, Error::ReservedIdentifier => error
        errors.add(self.class.tenant_identifier, error.message)
      end

      def tenancy_identifier_must_not_change
        attribute = self.class.tenant_identifier
        errors.add(attribute, "cannot be changed after creation") if will_save_change_to_attribute?(attribute)
      end
    end
  end
end
