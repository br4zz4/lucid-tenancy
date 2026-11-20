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
        base.around_command { |connection, block| Lucid::Tenancy.with(tenant: connection.tenant_identifier.presence, &block) }
      end

      def connect
        self.tenant_identifier = Resolver.identifier(request)
        super if defined?(super)
      end
    end
  end
end
