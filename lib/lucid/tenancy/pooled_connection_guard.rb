module Lucid
  module Tenancy
    # Refuses to boot on a connection that goes through a transaction-mode pooler.
    #
    # The gem isolates tenants with +SET search_path+, which is session state. A pooler in
    # transaction mode (e.g. Neon's +-pooler+ endpoint) can run each transaction on a different
    # real connection, so the path is lost (queries fail) or, worse, belongs to another tenant
    # (queries read and write the wrong schema without any error).
    module PooledConnectionGuard
      POOLER_HOST = /-pooler(\.|\z)/

      module_function

      # @raise [Error::PooledConnection] when the primary database host names a pooler
      def check!(configuration = Lucid::Tenancy.configuration)
        return if configuration.allow_pooled_connection

        host = primary_host
        return unless host&.match?(POOLER_HOST)

        raise Error::PooledConnection,
              "the database host #{host.inspect} is a connection pooler endpoint. " \
              "lucid-tenancy isolates tenants with SET search_path, which a transaction-mode pooler does not keep, " \
              "so queries can fail or hit another tenant's schema. Use the direct (non-pooled) endpoint, " \
              "or set config.allow_pooled_connection = true if the pool keeps session state."
      end

      # @return [String, nil] host of the primary database configuration
      def primary_host
        config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env.to_s, include_hidden: false).first
        return unless config

        host = config.respond_to?(:host) ? config.host : nil
        host ||= URI.parse(config.url.to_s).host if config.respond_to?(:url) && config.url.to_s.include?("://")
        host
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
