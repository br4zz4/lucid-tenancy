module Lucid
  module Tenancy
    # The tenant of the current thread or fiber.
    module State
      KEY = :lucid_tenancy_current_tenant

      def self.tenant
        ActiveSupport::IsolatedExecutionState[KEY]
      end

      def self.tenant=(tenant)
        ActiveSupport::IsolatedExecutionState[KEY] = tenant
      end
    end
  end
end
