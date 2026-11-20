require "test_helper"
require "open3"
require "rbconfig"

class AutoloadTest < TenancyTest
  LIB = File.expand_path("../../../lib", __dir__)

  def run_ruby(script)
    Open3.capture3(RbConfig.ruby, "-I", LIB, "-e", script)
  end

  def test_action_cable_module_resolves_without_an_explicit_require
    # arrange
    script = 'require "lucid/tenancy"; print Lucid::Tenancy::ActionCable.instance_of?(Module)'

    # act
    stdout, stderr, status = run_ruby(script)

    # assert
    assert status.success?, stderr
    assert_equal "true", stdout
  end

  def test_rspec_module_resolves_without_an_explicit_require
    # arrange
    script = 'require "lucid/tenancy"; print Lucid::Tenancy::RSpec.respond_to?(:configure!)'

    # act
    stdout, stderr, status = run_ruby(script)

    # assert
    assert status.success?, stderr
    assert_equal "true", stdout
  end

  def test_action_cable_and_rspec_are_declared_as_autoloads
    # arrange
    script = 'require "lucid/tenancy"; print [Lucid::Tenancy.autoload?(:ActionCable), Lucid::Tenancy.autoload?(:RSpec)].inspect'

    # act
    stdout, stderr, status = run_ruby(script)

    # assert
    assert status.success?, stderr
    assert_equal '["lucid/tenancy/action_cable", "lucid/tenancy/rspec"]', stdout
  end
end
