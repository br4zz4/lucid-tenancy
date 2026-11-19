module Lucid
  module Tenancy
    # Lets a migration declare where it runs.
    #
    # @example
    #   class AddCpfToStudents < ActiveRecord::Migration[8.1]
    #     tenancy :tenant
    #   end
    module Migration
      def self.included(base)
        base.extend(ClassMethods)
        base.class_attribute :tenancy_mode, instance_accessor: false, instance_predicate: false, default: nil
      end

      module ClassMethods
        # Declares whether the migration runs once in the shared schema or in every tenant schema.
        #
        # @param mode [Symbol] +:tenant+ or +:shared+
        # @raise [ArgumentError] unknown mode
        def tenancy(mode)
          raise ArgumentError, "tenancy must be :tenant or :shared, got #{mode.inspect}" unless Model::MODES.include?(mode)

          self.tenancy_mode = mode
        end
      end
    end
  end
end
