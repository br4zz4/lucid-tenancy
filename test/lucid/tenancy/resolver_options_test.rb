require "test_helper"

class ResolverOptionsTest < TenancyTest
  Resolver = Lucid::Tenancy::Resolver

  def setup
    super
    Lucid::Tenancy.configure { |config| config.base_domain = "app.test" }
  end

  def request_for(host)
    Rack::Request.new(Rack::MockRequest.env_for("http://#{host}/"))
  end

  def test_defaults
    # act
    config = Lucid::Tenancy.configuration

    # assert
    assert_equal [], config.ignored_identifiers
    assert_equal false, config.strict_base_domain
  end

  def test_ignored_identifier_resolves_to_nil_with_the_default_rule
    # arrange
    Lucid::Tenancy.configure { |config| config.ignored_identifiers = ["www"] }

    # act
    ignored = Resolver.identifier(request_for("www.app.test"))
    other = Resolver.identifier(request_for("acme.app.test"))

    # assert
    assert_nil ignored
    assert_equal "acme", other
  end

  def test_ignored_identifier_is_case_insensitive
    # arrange
    Lucid::Tenancy.configure { |config| config.ignored_identifiers = ["WWW"] }

    # act
    identifier = Resolver.identifier(request_for("Www.app.test"))

    # assert
    assert_nil identifier
  end

  def test_ignored_identifier_applies_to_a_custom_resolver
    # arrange
    Lucid::Tenancy.configure do |config|
      config.ignored_identifiers = ["Admin"]
      config.resolver = ->(_request) { "admin" }
    end

    # act
    identifier = Resolver.identifier(request_for("whatever.app.test"))

    # assert
    assert_nil identifier
  end

  def test_custom_resolver_value_not_ignored_passes_through
    # arrange
    Lucid::Tenancy.configure do |config|
      config.ignored_identifiers = ["www"]
      config.resolver = ->(_request) { "acme" }
    end

    # act
    identifier = Resolver.identifier(request_for("x.app.test"))

    # assert
    assert_equal "acme", identifier
  end

  def test_foreign_host_is_resolved_by_the_custom_resolver_when_not_strict
    # arrange
    Lucid::Tenancy.configure { |config| config.resolver = ->(_request) { "acme" } }

    # act
    identifier = Resolver.identifier(request_for("evil.test"))

    # assert
    assert_equal "acme", identifier
  end

  def test_strict_base_domain_rejects_a_foreign_host_without_calling_the_custom_resolver
    # arrange
    calls = []
    Lucid::Tenancy.configure do |config|
      config.strict_base_domain = true
      config.resolver = ->(_request) { calls << :called; "acme" }
    end

    # act
    identifier = Resolver.identifier(request_for("evil.test"))

    # assert
    assert_nil identifier
    assert_empty calls
  end

  def test_strict_base_domain_still_resolves_hosts_under_the_base_domain
    # arrange
    Lucid::Tenancy.configure do |config|
      config.strict_base_domain = true
      config.resolver = ->(_request) { "acme" }
    end

    # act
    sub = Resolver.identifier(request_for("x.app.test:3000"))
    bare = Resolver.identifier(request_for("app.test"))

    # assert
    assert_equal "acme", sub
    assert_equal "acme", bare
  end

  def test_strict_base_domain_does_not_match_a_lookalike_suffix
    # arrange
    Lucid::Tenancy.configure do |config|
      config.strict_base_domain = true
      config.resolver = ->(_request) { "acme" }
    end

    # act
    identifier = Resolver.identifier(request_for("notapp.test"))

    # assert
    assert_nil identifier
  end

  def test_strict_base_domain_without_base_domain_does_not_reject
    # arrange
    Lucid::Tenancy.configure do |config|
      config.base_domain = nil
      config.strict_base_domain = true
      config.resolver = ->(_request) { "acme" }
    end

    # act
    identifier = Resolver.identifier(request_for("evil.test"))

    # assert
    assert_equal "acme", identifier
  end

  def test_strict_base_domain_with_default_rule_keeps_subdomain
    # arrange
    Lucid::Tenancy.configure { |config| config.strict_base_domain = true }

    # act
    identifier = Resolver.identifier(request_for("acme.app.test"))

    # assert
    assert_equal "acme", identifier
  end
end
