require "test_helper"
require "rails/generators/test_case"
require "generators/lucid/tenancy/install/install_generator"

class InstallGeneratorOptionsTest < Rails::Generators::TestCase
  tests Lucid::Tenancy::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator_options", __dir__)

  setup :prepare_destination

  INITIALIZER = "config/initializers/lucid_tenancy.rb".freeze

  def test_initializer_lists_ignored_identifiers_commented
    # act
    run_generator

    # assert
    assert_file INITIALIZER, /^\s*#\s*config\.ignored_identifiers = %w\[www\]/
  end

  def test_initializer_lists_strict_base_domain_commented
    # act
    run_generator

    # assert
    assert_file INITIALIZER, /^\s*#\s*config\.strict_base_domain = false/
  end

  def test_initializer_lists_allow_pooled_connection_commented
    # act
    run_generator

    # assert
    assert_file INITIALIZER, /^\s*#\s*config\.allow_pooled_connection = false/
  end
end
