require "test_helper"

class ConnectionExtensionTest < TenancyTest
  def setup
    super
    use_dump(VALID_DUMP)
    define_tenant_model
    Lucid::Tenancy.configure { |config| config.tenant_model = "TtOrganization" }
    @alfa = provision_tenant(TtOrganization, "alfa")
    @secondary = nil
  end

  def teardown
    @secondary&.disconnect!
    super
  end

  def secondary_pool
    primary = ActiveRecord::Base.connection_pool
    db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "cache", primary.db_config.configuration_hash)
    pool_config = ActiveRecord::ConnectionAdapters::PoolConfig.new(ActiveRecord::Base, db_config, :writing, :default)
    @secondary = ActiveRecord::ConnectionAdapters::ConnectionPool.new(pool_config)
  end

  def test_reconnect_inside_a_tenant_keeps_its_search_path
    # arrange
    Lucid::Tenancy.set(tenant: @alfa)

    # act
    connection.reconnect!
    schema = current_schema

    # assert
    assert_equal @alfa.schema_name, schema
  end

  def test_verify_after_disconnect_inside_a_tenant_keeps_its_search_path
    # arrange
    Lucid::Tenancy.set(tenant: @alfa)

    # act
    connection.disconnect!
    connection.verify!
    schema = current_schema

    # assert
    assert_equal @alfa.schema_name, schema
  end

  def test_reconnect_without_a_tenant_stays_in_shared
    # arrange
    connection.reconnect!

    # act
    schema = current_schema

    # assert
    assert_equal "public", schema
  end

  def test_checkout_applies_the_tenant_search_path_on_the_primary_pool
    # arrange
    Lucid::Tenancy::State.tenant = @alfa

    # act
    path = ActiveRecord::Base.connection_pool.with_connection do |conn|
      conn.lucid_tenancy_checkout
      conn.select_value("SHOW search_path")
    end

    # assert
    assert_includes path, @alfa.schema_name
  end

  def test_primary_pool_connection_is_primary
    # arrange
    conn = ActiveRecord::Base.connection_pool.checkout

    # act
    primary = conn.lucid_tenancy_primary?
    ActiveRecord::Base.connection_pool.checkin(conn)

    # assert
    assert primary
  end

  def test_secondary_pool_connection_is_not_primary
    # arrange
    pool = secondary_pool

    # act
    primary = pool.with_connection { |conn| conn.lucid_tenancy_primary? }

    # assert
    refute primary
  end

  def test_checkout_on_a_secondary_pool_does_not_apply_the_tenant_search_path
    # arrange
    Lucid::Tenancy::State.tenant = @alfa
    pool = secondary_pool

    # act
    path = pool.with_connection do |conn|
      conn.lucid_tenancy_checkout
      conn.select_value("SHOW search_path")
    end

    # assert
    refute_includes path, @alfa.schema_name
  end

  def test_reconnect_on_a_secondary_pool_does_not_apply_the_tenant_search_path
    # arrange
    Lucid::Tenancy::State.tenant = @alfa
    pool = secondary_pool

    # act
    path = pool.with_connection do |conn|
      conn.reconnect!
      conn.select_value("SHOW search_path")
    end

    # assert
    refute_includes path, @alfa.schema_name
  end
end
