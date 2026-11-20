require "test_helper"
require "open3"
require "rbconfig"

class PooledConnectionGuardTest < TenancyTest
  Guard = Lucid::Tenancy::PooledConnectionGuard
  POOLED = "ep-x-pooler.c-2.sa-east-1.aws.neon.tech".freeze
  DIRECT = "ep-x.c-2.sa-east-1.aws.neon.tech".freeze

  def with_host(host)
    original = Guard.method(:primary_host)
    Guard.define_singleton_method(:primary_host) { host }
    yield
  ensure
    Guard.define_singleton_method(:primary_host, original)
  end

  def with_configs(configs)
    defined_env = nil
    registry = ActiveRecord::Base.configurations
    defined_env = !Rails.respond_to?(:env)
    Rails.define_singleton_method(:env) { "production" } if defined_env
    original = registry.method(:configs_for)
    registry.define_singleton_method(:configs_for) { |**| configs }
    yield
  ensure
    registry.singleton_class.send(:remove_method, :configs_for)
    Rails.singleton_class.send(:remove_method, :env) if defined_env
  end

  def probe(env)
    Dir.mktmpdir("probe") do |dir|
      path = File.join(dir, "probe.rb")
      File.write(path, <<~RUBY)
        require "rails"
        require "active_record/railtie"
        require "lucid/tenancy"
        class ProbeApp < Rails::Application
          config.eager_load = false
          config.secret_key_base = "x"
          config.logger = Logger.new(nil)
        end
        Lucid::Tenancy::PooledConnectionGuard.define_singleton_method(:check!) { |*| puts "CHECKED" }
        ProbeApp.initialize!
      RUBY
      lib = File.expand_path("../../../lib", __dir__)
      out, = Open3.capture2({ "RAILS_ENV" => env }, RbConfig.ruby, "-W0", "-I", lib, path, err: File::NULL)
      out
    end
  end

  def test_pooler_host_raises_citing_host_and_the_escape_option
    # arrange
    error = nil

    # act
    with_host(POOLED) { error = assert_raises(Lucid::Tenancy::Error::PooledConnection) { Guard.check! } }

    # assert
    assert_includes error.message, POOLED
    assert_includes error.message, "allow_pooled_connection"
  end

  def test_direct_host_does_not_raise
    # act & assert
    with_host(DIRECT) { Guard.check! }
  end

  def test_pooler_host_does_not_raise_when_allowed
    # arrange
    Lucid::Tenancy.configure { |config| config.allow_pooled_connection = true }

    # act & assert
    with_host(POOLED) { Guard.check! }
  end

  def test_allow_pooled_connection_defaults_to_false
    # act
    config = Lucid::Tenancy::Configuration.new

    # assert
    assert_equal false, config.allow_pooled_connection
  end

  def test_nil_host_does_not_raise
    # act & assert
    with_host(nil) { Guard.check! }
  end

  def test_pooler_only_in_the_middle_of_the_name_does_not_match
    # act & assert
    with_host("my-pooler-fan.example.com") { Guard.check! }
  end

  def test_pooler_at_the_end_of_the_name_matches
    # act & assert
    with_host("db-pooler") { assert_raises(Lucid::Tenancy::Error::PooledConnection) { Guard.check! } }
  end

  def test_primary_host_reads_the_host_key
    # arrange
    config = ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "primary", { adapter: "postgresql", host: POOLED })

    # act
    host = with_configs([config]) { Guard.primary_host }

    # assert
    assert_equal POOLED, host
  end

  def test_primary_host_reads_the_url
    # arrange
    config = ActiveRecord::DatabaseConfigurations::UrlConfig.new("production", "primary", "postgres://u:p@#{DIRECT}/db", { adapter: "postgresql" })

    # act
    host = with_configs([config]) { Guard.primary_host }

    # assert
    assert_equal DIRECT, host
  end

  def test_primary_host_is_nil_without_a_configuration
    # act
    host = with_configs([nil]) { Guard.primary_host }

    # assert
    assert_nil host
  end

  def test_railtie_runs_the_guard_in_production
    # act
    output = probe("production")

    # assert
    assert_includes output, "CHECKED"
  end

  def test_railtie_does_not_run_the_guard_in_development_or_test
    # act
    outputs = %w[development test].map { |env| probe(env) }

    # assert
    outputs.each { |output| refute_includes output, "CHECKED" }
  end
end
