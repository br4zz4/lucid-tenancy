require "ipaddr"

module Lucid
  module Tenancy
    # Finds the tenant identifier of a request.
    module Resolver
      module_function

      # @return [String, nil] the identifier, or +nil+ when the request names no tenant
      def identifier(request)
        custom = Lucid::Tenancy.configuration.resolver
        return custom.call(request) if custom

        subdomain(host(request))
      end

      # @return [String, nil] the part of +host+ before +config.base_domain+
      def subdomain(host)
        base = Lucid::Tenancy.configuration.base_domain
        return nil if host.blank? || base.blank?

        host = host.split(":").first.downcase
        return nil unless host.end_with?(".#{base.downcase}")

        host.delete_suffix(".#{base.downcase}").presence
      end

      # The host of the request. X-Forwarded-Host is used only when the request comes from a trusted proxy.
      def host(request)
        forwarded = request.get_header("HTTP_X_FORWARDED_HOST")
        return own_host(request) if forwarded.blank? || !trusted?(request.get_header("REMOTE_ADDR"))

        forwarded.split(",").first.strip
      end

      # The host the client connected to, never X-Forwarded-Host (Rack would use it for any caller).
      def own_host(request)
        request.get_header("HTTP_HOST").presence || request.get_header("SERVER_NAME").to_s
      end

      def trusted?(address)
        return false if address.blank?

        Lucid::Tenancy.configuration.trusted_proxies.any? do |proxy|
          IPAddr.new(proxy.to_s).include?(IPAddr.new(address))
        rescue IPAddr::InvalidAddressError
          false
        end
      end
    end
  end
end
