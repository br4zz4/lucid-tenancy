module Lucid
  module Tenancy
    # Makes Lucid::Tenancy enumerable over the tenants. The block of each element runs in
    # the schema of that tenant and the previous schema is restored afterwards.
    #
    # @example
    #   Lucid::Tenancy.each { |tenant| Student.count }
    #   Lucid::Tenancy.map { |tenant| [tenant.subdomain, Student.count] }.to_h
    module Collection
      include Enumerable

      def each
        return enum_for(:each) unless block_given?

        to_a.each { |tenant| with(tenant: tenant) { yield tenant } }
      end

      # @return [Array] the tenants, without switching schema
      def to_a
        shared { tenant_class.order(tenant_class.primary_key).to_a }
      end

      # @return [Integer] how many tenants exist
      def count(*args, &block)
        return super if args.any? || block

        shared { tenant_class.count }
      end

      alias_method :size, :count
    end
  end
end
