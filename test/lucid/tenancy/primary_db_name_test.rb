require "test_helper"

class PrimaryDbNameTest < TenancyTest
  def setup
    super
    @established = ActiveRecord::Base.connection_db_config.configuration_hash
    @pool_config = ActiveRecord::Base.connection_pool.db_config
  end

  def teardown
    ActiveRecord::Base.singleton_class.send(:remove_method, :connection_pool) if ActiveRecord::Base.singleton_class.method_defined?(:connection_pool, false)
    ActiveRecord::Base.establish_connection(@established) unless ActiveRecord::Base.connected?
    super
  end

  def without_base_pool
    ActiveRecord::Base.define_singleton_method(:connection_pool) { raise ActiveRecord::ConnectionNotDefined, "stubbed" }
    yield
  ensure
    ActiveRecord::Base.singleton_class.send(:remove_method, :connection_pool)
  end

  def detached_pool(name)
    db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", name, @established)
    pool_config = ActiveRecord::ConnectionAdapters::PoolConfig.new(ActiveRecord::Base, db_config, :writing, :default)
    ActiveRecord::ConnectionAdapters::ConnectionPool.new(pool_config)
  end

  def expected_primary
    ActiveRecord::Base.configurations.configs_for(env_name: ActiveRecord::ConnectionHandling::DEFAULT_ENV.call).first&.name
  end

  def test_primary_db_name_returns_the_name_of_the_connected_pool
    # arrange
    expected = @pool_config.name

    # act
    name = Lucid::Tenancy.primary_db_name

    # assert
    assert_equal expected, name
  end

  def test_primary_db_name_falls_back_to_the_first_config_when_base_has_no_pool
    # arrange
    expected = expected_primary

    # act
    name = without_base_pool { Lucid::Tenancy.primary_db_name }

    # assert
    assert_equal expected, name
  end

  def test_primary_db_name_does_not_raise_after_the_base_connection_is_removed
    # arrange
    expected = expected_primary
    ActiveRecord::Base.remove_connection

    # act
    name = Lucid::Tenancy.primary_db_name

    # assert
    assert_equal expected, name
  end

  def test_checking_out_from_a_primary_pool_without_base_pool_does_not_raise
    # arrange
    pool = detached_pool(expected_primary || @pool_config.name)

    # act
    result = without_base_pool { pool.with_connection { |conn| conn.lucid_tenancy_primary? } }

    # assert
    assert_equal pool.db_config.name == expected_primary, result
  ensure
    pool&.disconnect!
  end

  def test_checking_out_from_a_secondary_pool_without_base_pool_is_not_primary
    # arrange
    pool = detached_pool("cache_other")

    # act
    result = without_base_pool { pool.with_connection { |conn| conn.lucid_tenancy_primary? } }

    # assert
    refute result
  ensure
    pool&.disconnect!
  end

  def test_shared_only_migrations_primary_pool_does_not_raise_without_base_pool
    # arrange
    context = Class.new(ActiveRecord::MigrationContext) { prepend Lucid::Tenancy::SharedOnlyMigrations }.new([])
    pool = detached_pool(expected_primary || @pool_config.name)
    context.define_singleton_method(:connection_pool) { pool }

    # act
    result = without_base_pool { context.send(:primary_pool?) }

    # assert
    assert result
  ensure
    pool&.disconnect!
  end
end
