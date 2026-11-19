module Lucid
  module Tenancy
    # Minitest helpers. Include it in a test case.
    #
    # @example
    #   class StudentTest < ActiveSupport::TestCase
    #     include Lucid::Tenancy::Minitest
    #     tenant "alfa"
    #   end
    module Minitest
      def self.included(base)
        base.extend(ClassMethods)
        base.class_attribute :lucid_tenancy_test_tenant, instance_accessor: false, default: nil
      end

      module ClassMethods
        # The tenant every test of the case runs in.
        def tenant(identifier)
          self.lucid_tenancy_test_tenant = identifier
        end
      end

      def before_setup
        super
        identifier = self.class.lucid_tenancy_test_tenant
        Lucid::Tenancy.set(tenant: identifier) if identifier
      end

      def after_teardown
        Lucid::Tenancy.set(tenant: nil)
        super
      end
    end
  end
end
