module Lucid
  module Tenancy
    # Identifies the tenant of an Action Cable connection from its host.
    #
    # @example
    #   module ApplicationCable
    #     class Connection < ActionCable::Connection::Base
    #       include Lucid::Tenancy::ActionCable
    #     end
    #   end
    module ActionCable
      def self.included(base)
        base.identified_by :tenant_identifier
        base.before_command { Lucid::Tenancy.set(tenant: tenant_identifier) if tenant_identifier }
        base.after_command { Lucid::Tenancy.set(tenant: nil) }
      end

      def connect
        self.tenant_identifier = Resolver.identifier(request)
        super if defined?(super)
      end
    end
  end
end
