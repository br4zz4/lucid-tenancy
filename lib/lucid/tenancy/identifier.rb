module Lucid
  module Tenancy
    # Turns the identifier of a tenant (a subdomain, a slug) into a safe schema name.
    #
    # Hyphens become underscores, the result must match +[a-z][a-z0-9_]{1,62}+ and
    # must not be a reserved name.
    module Identifier
      FORMAT = /\A[a-z][a-z0-9_]{1,62}\z/
      BUILT_IN_RESERVED = ["public", "information_schema", /\Apg_/].freeze

      # @return [String] the schema name for +identifier+
      # @raise [Error::InvalidIdentifier] it does not become a valid schema name
      # @raise [Error::ReservedIdentifier] it is a name the gem never uses for a tenant
      def self.schema_for(identifier)
        schema = identifier.to_s.strip.downcase.tr("-", "_")
        raise Error::InvalidIdentifier, "#{identifier.inspect} is not a valid tenant identifier" unless FORMAT.match?(schema)
        raise Error::ReservedIdentifier, "#{schema.inspect} is reserved" if reserved?(schema)

        schema
      end

      # @return [Boolean]
      def self.valid?(identifier)
        schema_for(identifier)
        true
      rescue Error::InvalidIdentifier, Error::ReservedIdentifier
        false
      end

      def self.reserved?(schema)
        reserved_names.any? { |name| name.is_a?(Regexp) ? name.match?(schema) : name.to_s == schema }
      end

      def self.reserved_names
        config = Lucid::Tenancy.configuration
        BUILT_IN_RESERVED + [config.template_schema, config.shared_schema] + config.reserved_identifiers
      end
    end
  end
end
