require "test_helper"
require "rails/generators/test_case"
require "generators/lucid/tenancy/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Lucid::Tenancy::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator", __dir__)

  setup :prepare_destination

  INITIALIZER = "config/initializers/lucid_tenancy.rb".freeze

  def test_creates_the_initializer
    # act
    run_generator

    # assert
    assert_file INITIALIZER
  end

  def test_initializer_configures_the_tenancy
    # act
    run_generator

    # assert
    assert_file INITIALIZER, /Lucid::Tenancy\.configure/
  end

  def test_initializer_sets_the_tenant_model
    # act
    run_generator

    # assert
    assert_file INITIALIZER, /^\s*config\.tenant_model = "Organization"/
  end

  def test_initializer_sets_the_tenant_identifier
    # act
    run_generator

    # assert
    assert_file INITIALIZER, /^\s*config\.tenant_identifier = :subdomain/
  end

  def test_initializer_lists_the_optional_settings_commented
    # act
    run_generator

    # assert
    %w[base_domain shared_paths on_missing_tenant trusted_proxies after_provision reserved_identifiers template_schema].each do |option|
      assert_file INITIALIZER, /^\s*#\s*config\.#{option}\b/
    end
  end
end
