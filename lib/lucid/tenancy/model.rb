module Lucid
  module Tenancy
    # Declares whether a model lives in the shared schema or in each tenant schema.
    #
    # @example
    #   class Organization < ApplicationRecord
    #     tenancy :shared
    #   end
    module Model
      MODES = %i[tenant shared].freeze

      def self.included(base)
        base.extend(ClassMethods)
        base.class_attribute :tenancy_mode, instance_accessor: false, instance_predicate: false, default: :tenant
      end

      module ClassMethods
        # Declares where the table of this model lives.
        #
        # @param mode [Symbol] +:tenant+ (default, one table per tenant schema) or +:shared+ (one table in the shared schema)
        # @raise [ArgumentError] unknown mode
        def tenancy(mode)
          raise ArgumentError, "tenancy must be one of #{MODES.inspect}, got #{mode.inspect}" unless MODES.include?(mode)

          self.tenancy_mode = mode
          return unless mode == :shared

          table = table_name.to_s.split(".").last
          self.table_name = "#{Lucid::Tenancy.configuration.shared_schema}.#{table}"
        end

        def shared_table?
          tenancy_mode == :shared
        end

        def tenant_table?
          tenancy_mode == :tenant
        end
      end
    end
  end
end
