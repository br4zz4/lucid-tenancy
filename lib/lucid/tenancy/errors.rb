module Lucid
  module Tenancy
    # Base class of every error raised by Lucid::Tenancy itself.
    class Error < StandardError
      # The identifier does not become a valid schema name.
      class InvalidIdentifier < Error; end

      # The identifier is a name the gem never uses for a tenant (public, the template, pg_*...).
      class ReservedIdentifier < Error; end

      # No tenant matches the given identifier.
      class TenantNotFound < Error; end

      # The tenant schema already exists.
      class AlreadyProvisioned < Error; end

      # A migration did not declare +tenancy :tenant+ or +tenancy :shared+.
      class MissingTenancyDeclaration < Error; end

      # The tenant model was declared twice with different settings.
      class ConfigurationConflict < Error; end
    end
  end
end
