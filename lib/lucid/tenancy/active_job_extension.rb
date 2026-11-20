module Lucid
  module Tenancy
    # Makes Active Job carry the tenant: a job enqueued inside a tenant runs in that tenant,
    # in the worker, and the previous schema is restored afterwards.
    #
    # A job that is not about a tenant declares +tenancy :shared+ and always runs in the shared schema.
    #
    # @example
    #   class CleanupJob < ApplicationJob
    #     tenancy :shared
    #   end
    module ActiveJobExtension
      KEY = "lucid_tenancy_tenant".freeze

      def self.included(base)
        base.extend(ClassMethods)
        base.class_attribute :tenancy_mode, instance_accessor: false, instance_predicate: false, default: :tenant
        base.around_perform { |job, block| job.send(:lucid_tenancy_perform, &block) }
      end

      module ClassMethods
        # @param mode [Symbol] +:tenant+ (default, runs where it was enqueued) or +:shared+
        def tenancy(mode)
          raise ArgumentError, "tenancy must be one of #{Model::MODES.inspect}, got #{mode.inspect}" unless Model::MODES.include?(mode)

          self.tenancy_mode = mode
        end
      end

      def initialize(*)
        super
        @lucid_tenancy_origin = Lucid::Tenancy.current
      end

      def serialize
        data = super
        tenant = @lucid_tenancy_origin || Lucid::Tenancy.current
        data[KEY] = lucid_tenancy_identifier(tenant) if tenant && self.class.tenancy_mode == :tenant
        data
      end

      def deserialize(job_data)
        super
        @lucid_tenancy_origin = nil
        @lucid_tenancy_schema = job_data[KEY]
      end

      private

      def lucid_tenancy_identifier(tenant)
        tenant.class.respond_to?(:tenant_identifier) ? tenant[tenant.class.tenant_identifier].to_s : tenant.schema_name
      end

      def lucid_tenancy_perform(&block)
        return Lucid::Tenancy.shared(&block) if self.class.tenancy_mode == :shared
        return Lucid::Tenancy.with(tenant: @lucid_tenancy_origin, &block) if !@lucid_tenancy_schema && @lucid_tenancy_origin
        return Lucid::Tenancy.shared(&block) unless @lucid_tenancy_schema

        Lucid::Tenancy.with(tenant: @lucid_tenancy_schema, &block)
      end
    end
  end
end
