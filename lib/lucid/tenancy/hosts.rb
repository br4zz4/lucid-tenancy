module Lucid
  module Tenancy
    # Helpers to build the hosts of the tenants from +config.base_domain+, never from the request.
    module Hosts
      STANDARD_PORTS = [80, 443].freeze

      module_function

      # Value for +config.hosts+: the base domain and all its subdomains.
      #
      # @example
      #   config.hosts = Lucid::Tenancy::Hosts.allowed
      #
      # @return [Array<String>] +[".example.com"]+
      # @raise [Lucid::Tenancy::Error::ConfigurationConflict] +base_domain+ is not set
      def allowed
        [".#{base_domain!}"]
      end

      # Value for +default_url_options+ of a tenant, built from the configured base domain only.
      #
      # @param tenant [#tenant_identifier] the tenant
      # @param port [Integer, String, nil] omitted from the result when blank, 80 or 443
      # @return [Hash] +{ host: "alfa.example.com" }+, plus +:port+ when it is not standard
      # @raise [Lucid::Tenancy::Error::ConfigurationConflict] +base_domain+ is not set
      def url_options_for(tenant, port: nil)
        options = { host: "#{tenant.tenant_identifier}.#{base_domain!}" }
        number = port.presence&.to_i
        options[:port] = number if number && !STANDARD_PORTS.include?(number)
        options
      end

      # @api private
      def base_domain!
        base = Lucid::Tenancy.configuration.base_domain
        return base if base.present?

        raise Error::ConfigurationConflict, "config.base_domain is not set"
      end
    end
  end
end
