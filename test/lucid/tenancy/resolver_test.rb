require "test_helper"

class ResolverTest < TenancyTest
  def setup
    super
    Lucid::Tenancy.configure do |config|
      config.base_domain = "app.test"
      config.trusted_proxies = ["10.0.0.0/8", "127.0.0.1"]
    end
  end

  def request_for(host, headers = {})
    env = Rack::MockRequest.env_for("http://#{host}/", headers)
    Rack::Request.new(env)
  end

  def test_identifier_is_the_subdomain_under_the_base_domain
    # arrange
    request = request_for("acme.app.test")

    # act
    identifier = Lucid::Tenancy::Resolver.identifier(request)

    # assert
    assert_equal "acme", identifier
  end

  def test_identifier_ignores_port_and_case
    # arrange
    request = request_for("ACME.App.Test:3000")

    # act
    identifier = Lucid::Tenancy::Resolver.identifier(request)

    # assert
    assert_equal "acme", identifier
  end

  def test_identifier_is_nil_for_the_bare_base_domain
    # arrange
    request = request_for("app.test")

    # act
    identifier = Lucid::Tenancy::Resolver.identifier(request)

    # assert
    assert_nil identifier
  end

  def test_identifier_is_nil_for_a_foreign_domain
    # arrange
    request = request_for("acme.other.test")

    # act
    identifier = Lucid::Tenancy::Resolver.identifier(request)

    # assert
    assert_nil identifier
  end

  def test_identifier_is_nil_without_a_base_domain
    # arrange
    Lucid::Tenancy.configuration.base_domain = nil
    request = request_for("acme.app.test")

    # act
    identifier = Lucid::Tenancy::Resolver.identifier(request)

    # assert
    assert_nil identifier
  end

  def test_custom_resolver_replaces_the_subdomain_rule
    # arrange
    Lucid::Tenancy.configuration.resolver = ->(request) { request.get_header("HTTP_X_TENANT") }
    request = request_for("acme.app.test", "HTTP_X_TENANT" => "globex")

    # act
    identifier = Lucid::Tenancy::Resolver.identifier(request)

    # assert
    assert_equal "globex", identifier
  end

  def test_subdomain_of_a_host
    # arrange
    host = "acme.app.test"

    # act
    subdomain = Lucid::Tenancy::Resolver.subdomain(host)

    # assert
    assert_equal "acme", subdomain
  end

  def test_subdomain_is_nil_for_blank_host
    # arrange
    host = nil

    # act
    subdomain = Lucid::Tenancy::Resolver.subdomain(host)

    # assert
    assert_nil subdomain
  end

  def test_forwarded_host_is_used_from_a_trusted_proxy_ip
    # arrange
    request = request_for("internal.local", "REMOTE_ADDR" => "127.0.0.1", "HTTP_X_FORWARDED_HOST" => "acme.app.test")

    # act
    host = Lucid::Tenancy::Resolver.host(request)

    # assert
    assert_equal "acme.app.test", host
  end

  def test_forwarded_host_is_used_from_a_trusted_proxy_cidr
    # arrange
    request = request_for("internal.local", "REMOTE_ADDR" => "10.1.2.3", "HTTP_X_FORWARDED_HOST" => "acme.app.test, other.test")

    # act
    identifier = Lucid::Tenancy::Resolver.identifier(request)

    # assert
    assert_equal "acme", identifier
  end

  def test_forwarded_host_is_ignored_from_an_untrusted_address
    # arrange
    request = request_for("real.app.test", "REMOTE_ADDR" => "203.0.113.9", "HTTP_X_FORWARDED_HOST" => "evil.app.test")

    # act
    identifier = Lucid::Tenancy::Resolver.identifier(request)

    # assert
    assert_equal "real", identifier
  end

  def test_forwarded_host_is_ignored_without_trusted_proxies
    # arrange
    Lucid::Tenancy.configuration.trusted_proxies = []
    request = request_for("real.app.test", "REMOTE_ADDR" => "127.0.0.1", "HTTP_X_FORWARDED_HOST" => "evil.app.test")

    # act
    identifier = Lucid::Tenancy::Resolver.identifier(request)

    # assert
    assert_equal "real", identifier
  end
end
