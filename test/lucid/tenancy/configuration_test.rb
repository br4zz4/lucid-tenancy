require "test_helper"

class ConfigurationTest < TenancyTest
  def test_defaults
    # arrange
    config = Lucid::Tenancy::Configuration.new

    # assert
    assert_nil config.tenant_model
    assert_equal :subdomain, config.tenant_identifier
    assert_equal "tenancy_template", config.template_schema
    assert_equal "public", config.shared_schema
    assert_equal [], config.reserved_identifiers
  end

  def test_configure_yields_and_persists
    # act
    result = Lucid::Tenancy.configure do |config|
      config.tenant_model = "Organization"
      config.tenant_identifier = :slug
    end

    # assert
    assert_same Lucid::Tenancy.configuration, result
    assert_equal "Organization", Lucid::Tenancy.configuration.tenant_model
    assert_equal :slug, Lucid::Tenancy.configuration.tenant_identifier
  end

  def test_reset_configuration_restores_defaults
    # arrange
    Lucid::Tenancy.configure { |config| config.shared_schema = "other" }

    # act
    Lucid::Tenancy.reset_configuration!

    # assert
    assert_equal "public", Lucid::Tenancy.configuration.shared_schema
  end
end
