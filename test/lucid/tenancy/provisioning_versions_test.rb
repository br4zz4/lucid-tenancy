require "migration_helper"

class ProvisioningVersionsTest < MigrationTenancyTest
  DUMP = <<~RUBY.freeze
    ActiveRecord::Schema[7.2].define(version: 3) do
      create_table :tags do |t|
        t.string :name
      end

      create_table :labels do |t|
        t.string :name
      end
    end
  RUBY

  CREATE_THINGS = "create_table(:things) { |t| t.string :label }".freeze
  CREATE_TAGS = "create_table(:tags) { |t| t.string :name }".freeze
  CREATE_LABELS = "create_table(:labels) { |t| t.string :name }".freeze
  CREATE_EXTRAS = "create_table(:extras) { |t| t.string :name }".freeze

  def setup
    super
    use_dump(DUMP)
    shared_only_migration_context
    @previous_paths = ActiveRecord::Migrator.migrations_paths
    ActiveRecord::Migrator.migrations_paths = [@migrations_dir]
    write_migration("20260101000001", "create_things", mode: :shared, body: CREATE_THINGS)
    write_migration("20260101000002", "create_tags", mode: :tenant, body: CREATE_TAGS)
    write_migration("20260101000003", "create_labels", mode: :tenant, body: CREATE_LABELS)
    use_dump(DUMP.sub("version: 3", "version: 20260101000003"))
    prepare_template
    Lucid::Tenancy::Schema.with_path(TEMPLATE) { Lucid::Tenancy::Migrator.register_dumped_versions(paths: [@migrations_dir]) }
  end

  def teardown
    @restore_pool&.call
    ActiveRecord::Migrator.migrations_paths = @previous_paths
    super
  end

  def shared_only_migration_context
    pool = ActiveRecord::Base.connection_pool
    original = pool.method(:migration_context)
    pool.define_singleton_method(:migration_context) { original.call.extend(Lucid::Tenancy::SharedOnlyMigrations) }
    @restore_pool = -> { pool.singleton_class.send(:remove_method, :migration_context) }
  end

  def provision(subdomain)
    tenant = @klass.create!(subdomain: subdomain)
    @test_schemas << tenant.schema_name
    Lucid::Tenancy.provision(tenant)
    tenant
  end

  def test_provision_registers_every_tenant_migration_up_to_the_dump_version
    # arrange
    tenant = @klass.create!(subdomain: "alfa")
    @test_schemas << tenant.schema_name

    # act
    Lucid::Tenancy.provision(tenant)
    registered = versions("alfa")

    # assert
    assert_includes registered, "20260101000002"
    assert_includes registered, "20260101000003"
  end

  def test_migrate_right_after_provision_does_not_raise_and_tenant_is_up_to_date
    # arrange
    provision("alfa")

    # act
    migrate
    pending = migrator.pending(paths: [@migrations_dir])

    # assert
    assert_equal [], pending["alfa"]
    assert_equal({ "public" => [], TEMPLATE => [], "alfa" => [] }, pending)
  end

  def test_migrations_newer_than_the_dump_stay_pending_in_a_new_tenant
    # arrange
    write_migration("20260101000009", "create_extras", mode: :tenant, body: CREATE_EXTRAS)
    provision("alfa")

    # act
    pending = migrator.pending(paths: [@migrations_dir])

    # assert
    refute_includes versions("alfa"), "20260101000009"
    assert_equal [20260101000009], pending["alfa"]
  end

  def test_newer_migration_runs_after_provision_without_rerunning_older_ones
    # arrange
    write_migration("20260101000009", "create_extras", mode: :tenant, body: CREATE_EXTRAS)
    provision("alfa")

    # act
    migrate

    # assert
    assert_includes versions("alfa"), "20260101000009"
    assert_includes connection.select_values("SELECT table_name FROM information_schema.tables WHERE table_schema = 'alfa'"), "extras"
  end

  def test_provision_and_migrate_work_with_query_cache_on
    # arrange
    write_migration("20260101000009", "create_extras", mode: :tenant, body: CREATE_EXTRAS)

    # act
    pending = ActiveRecord::Base.cache do
      provision("alfa")
      registered = versions("alfa")
      before = migrator.pending(paths: [@migrations_dir])
      migrate
      [registered, before, migrator.pending(paths: [@migrations_dir])]
    end

    # assert
    assert_includes pending[0], "20260101000002"
    assert_includes pending[0], "20260101000003"
    assert_equal [20260101000009], pending[1]["alfa"]
    assert_equal [], pending[2]["alfa"]
  end
end
