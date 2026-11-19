require "test_helper"

class TestHelpersTest < TenancyTest
  def setup
    super
    use_dump(VALID_DUMP)
    define_tenant_model
    Lucid::Tenancy.configure { |config| config.tenant_model = "TtOrganization" }
    @alfa = provision_tenant(TtOrganization, "alfa")
  end

  def build_case(identifier)
    klass = Class.new(Minitest::Test) do
      include Lucid::Tenancy::Minitest
    end
    klass.tenant(identifier) if identifier
    klass
  end

  def test_tenant_macro_stores_the_identifier_per_case
    # arrange
    with_tenant = build_case("alfa")
    without = build_case(nil)

    # act & assert
    assert_equal "alfa", with_tenant.lucid_tenancy_test_tenant
    assert_nil without.lucid_tenancy_test_tenant
  end

  def test_before_setup_sets_the_tenant_and_after_teardown_clears_it
    # arrange
    test_case = build_case("alfa").new("noop")

    # act
    test_case.before_setup
    during = [Lucid::Tenancy.current&.schema_name, current_schema]
    test_case.after_teardown

    # assert
    assert_equal [@alfa.schema_name, @alfa.schema_name], during
    assert_nil Lucid::Tenancy.current
    assert_equal "public", current_schema
  end

  def test_running_a_real_test_executes_it_inside_the_tenant
    # arrange
    seen = []
    klass = build_case("alfa")
    klass.define_method(:test_probe) { seen << [Lucid::Tenancy.current&.schema_name, ActiveRecord::Base.lease_connection.select_value("SELECT current_schema()")] }
    Object.const_set("TtProbeCase", klass)
    @test_constants << "TtProbeCase"

    # act
    result = klass.new("test_probe").run

    # assert
    assert result.passed?
    assert_equal [[@alfa.schema_name, @alfa.schema_name]], seen
    assert_nil Lucid::Tenancy.current
    assert_equal "public", current_schema
  end

  def test_case_without_tenant_stays_in_shared
    # arrange
    test_case = build_case(nil).new("noop")

    # act
    test_case.before_setup
    during = Lucid::Tenancy.current
    test_case.after_teardown

    # assert
    assert_nil during
    assert_equal "public", current_schema
  end

  def test_rspec_file_loads_without_rspec_defined
    # arrange
    skip "RSpec is loaded" if defined?(::RSpec)

    # act
    loaded = require "lucid/tenancy/rspec"

    # assert
    assert_includes [true, false], loaded
    assert_respond_to Lucid::Tenancy::RSpec, :configure!
  end

  def test_rspec_configure_registers_an_around_hook
    # arrange
    skip "rspec-core is not in the bundle" unless Gem.loaded_specs.key?("rspec-core") || begin
      require "rspec/core"
      true
    rescue LoadError
      false
    end
    require "lucid/tenancy/rspec"

    # act
    Lucid::Tenancy::RSpec.configure!

    # assert
    assert_respond_to Lucid::Tenancy::RSpec, :configure!
  end
end
