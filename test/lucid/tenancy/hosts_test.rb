require "test_helper"

class HostsTest < TenancyTest
  Hosts = Lucid::Tenancy::Hosts

  def setup
    super
    Lucid::Tenancy.configure { |config| config.base_domain = "app.test" }
    @tenant = FakeIdentified.new("alfa")
  end

  FakeIdentified = Struct.new(:tenant_identifier)

  def test_allowed_is_the_base_domain_and_its_subdomains
    # act
    allowed = Hosts.allowed

    # assert
    assert_equal [".app.test"], allowed
  end

  def test_allowed_raises_without_base_domain
    # arrange
    Lucid::Tenancy.configure { |config| config.base_domain = nil }

    # act
    error = assert_raises(Lucid::Tenancy::Error::ConfigurationConflict) { Hosts.allowed }

    # assert
    assert_match(/base_domain/, error.message)
  end

  def test_url_options_has_only_the_host_without_port
    # act
    options = Hosts.url_options_for(@tenant)

    # assert
    assert_equal({ host: "alfa.app.test" }, options)
  end

  def test_url_options_includes_a_non_standard_port
    # act
    options = Hosts.url_options_for(@tenant, port: 3000)

    # assert
    assert_equal({ host: "alfa.app.test", port: 3000 }, options)
  end

  def test_url_options_converts_a_string_port
    # act
    options = Hosts.url_options_for(@tenant, port: "3000")

    # assert
    assert_equal({ host: "alfa.app.test", port: 3000 }, options)
  end

  def test_url_options_omits_nil_blank_and_standard_ports
    # act
    results = [nil, "", 80, 443, "80", "443"].map { |port| Hosts.url_options_for(@tenant, port: port) }

    # assert
    results.each { |options| assert_equal({ host: "alfa.app.test" }, options) }
  end

  def test_url_options_raises_without_base_domain
    # arrange
    Lucid::Tenancy.configure { |config| config.base_domain = nil }

    # act & assert
    assert_raises(Lucid::Tenancy::Error::ConfigurationConflict) { Hosts.url_options_for(@tenant) }
  end

  def test_url_options_uses_the_configured_base_domain_not_a_request_host
    # arrange
    Lucid::Tenancy.configure { |config| config.base_domain = "other.test" }

    # act
    options = Hosts.url_options_for(@tenant)

    # assert
    assert_equal "alfa.other.test", options[:host]
  end

  def test_tenant_identifier_is_the_default_identifying_attribute
    # arrange
    klass = define_tenant_model
    tenant = klass.new(subdomain: "alfa")

    # act
    identifier = tenant.tenant_identifier

    # assert
    assert_equal "alfa", identifier
  end

  def test_tenant_identifier_follows_a_custom_identifying_attribute
    # arrange
    klass = define_tenant_model("TtOrganization", identifier: :subdomain)
    tenant = klass.new(subdomain: "beta")

    # act
    identifier = tenant.tenant_identifier

    # assert
    assert_equal "beta", identifier
  end

  def test_url_options_accepts_a_real_tenant
    # arrange
    klass = define_tenant_model
    tenant = klass.new(subdomain: "gama")

    # act
    options = Hosts.url_options_for(tenant, port: 3000)

    # assert
    assert_equal({ host: "gama.app.test", port: 3000 }, options)
  end
end
