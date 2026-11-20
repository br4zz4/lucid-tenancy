require "migration_helper"

class MigratorRegressionTest < MigrationTenancyTest
  ADD_NICKNAME = "add_column :students, :nickname, :string".freeze

  def setup
    super
    prepare_template
  end

  def secondary_pool
    primary = ActiveRecord::Base.connection_pool
    db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "cache", primary.db_config.configuration_hash)
    pool_config = ActiveRecord::ConnectionAdapters::PoolConfig.new(ActiveRecord::Base, db_config, :writing, :default)
    @secondary = ActiveRecord::ConnectionAdapters::ConnectionPool.new(pool_config)
  end

  def teardown
    @secondary&.disconnect!
    super
  end

  def test_rollback_ignores_a_tenant_version_orphaned_in_public
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate
    connection.execute("INSERT INTO public.schema_migrations (version) VALUES ('20260101000001')")

    # act
    rollback(steps: 1)

    # assert
    refute_includes columns("alfa", "students"), "nickname"
    refute_includes columns(TEMPLATE, "students"), "nickname"
    assert_equal %w[3], versions("alfa")
    assert_equal %w[3], versions(TEMPLATE)
    assert_includes versions("public"), "20260101000001"
  end

  def test_rollback_ignores_an_unknown_version_in_public
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate
    connection.execute("INSERT INTO public.schema_migrations (version) VALUES ('20991231235959')")

    # act
    rollback(steps: 1)

    # assert
    refute_includes columns("alfa", "students"), "nickname"
    assert_equal %w[3], versions("alfa")
    assert_includes versions("public"), "20991231235959"
  end

  def test_shared_only_migrations_returns_every_migration_for_another_pool
    # arrange
    write_migration("20260101000001", "create_things", mode: :shared, body: "create_table(:things) { |t| t.string :name }")
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    pool = secondary_pool
    schema_migration = ActiveRecord::SchemaMigration.new(pool)
    internal_metadata = ActiveRecord::InternalMetadata.new(pool)
    klass = Class.new(ActiveRecord::MigrationContext) { prepend Lucid::Tenancy::SharedOnlyMigrations }
    context = klass.new([@migrations_dir], schema_migration, internal_metadata)
    context.define_singleton_method(:connection_pool) { pool }

    # act
    visible = context.migrations.map(&:version)

    # assert
    assert_equal [20260101000001, 20260101000002], visible
  end

  def test_shared_only_migrations_filters_on_the_primary_pool
    # arrange
    write_migration("20260101000001", "create_things", mode: :shared, body: "create_table(:things) { |t| t.string :name }")
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    klass = Class.new(ActiveRecord::MigrationContext) { prepend Lucid::Tenancy::SharedOnlyMigrations }

    # act
    visible = klass.new([@migrations_dir]).migrations.map(&:version)

    # assert
    assert_equal [20260101000001], visible
  end

  def test_baseline_seeds_an_existing_empty_version_table
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate
    connection.execute(%(DELETE FROM "alfa".schema_migrations))

    # act
    Lucid::Tenancy.baseline("alfa")

    # assert
    assert_equal %w[20260101000001 3], versions("alfa")
    assert_equal versions(TEMPLATE), versions("alfa")
  end

  def test_baseline_does_not_duplicate_or_overwrite_existing_versions
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate
    connection.execute(%(INSERT INTO "alfa".schema_migrations (version) VALUES ('20250101000000')))

    # act
    2.times { Lucid::Tenancy.baseline("alfa") }

    # assert
    assert_equal %w[20250101000000 20260101000001 3], versions("alfa")
  end

  def test_baseline_on_an_empty_table_without_a_template_source_leaves_it_empty
    # arrange
    provision_all("alfa")
    connection.execute(%(DELETE FROM "alfa".schema_migrations))
    connection.execute(%(DROP SCHEMA "#{TEMPLATE}" CASCADE))

    # act
    Lucid::Tenancy.baseline("alfa")

    # assert
    assert_empty versions("alfa")
  end
end
