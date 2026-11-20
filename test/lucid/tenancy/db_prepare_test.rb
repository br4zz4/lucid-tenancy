require "migration_helper"
require "rake"

class DbPrepareTest < MigrationTenancyTest
  RAKEFILE = File.expand_path("../../../lib/tasks/lucid_tenancy.rake", __dir__)

  def setup
    super
    prepare_template
    @path = Lucid::Tenancy.configuration.tenant_schema_path
    @order = []
    @rake = Rake::Application.new
    Rake.application = @rake
    Rake::Task.define_task("db:load_config")
    order = @order
    native_probe = -> { order << [:native, columns("alfa", "students").include?("nickname")] }
    Rake::Task.define_task("db:prepare") { native_probe.call }
    load RAKEFILE
    @pool = ActiveRecord::Base.connection_pool
    @original_paths = @pool.migration_context.instance_variable_get(:@migrations_paths)
    ActiveRecord::Migrator.migrations_paths = [@migrations_dir]
  end

  def teardown
    ActiveRecord::Migrator.migrations_paths = @original_paths || ["db/migrate"]
    Rake.application = Rake::Application.new
    super
  end

  def test_prepare_runs_the_migrator_after_the_native_prepare
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: "add_column :students, :nickname, :string")

    # act
    silence { @rake["db:prepare"].invoke }

    # assert
    assert_equal [[:native, false]], @order
    assert_includes columns("alfa", "students"), "nickname"
    assert_includes columns(TEMPLATE, "students"), "nickname"
    assert_includes versions("alfa"), "20260101000001"
  end

  def test_prepare_writes_the_tenant_dump_after_migrating
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: "add_column :students, :nickname, :string")

    # act
    silence { @rake["db:prepare"].invoke }

    # assert
    assert_includes File.read(@path), %(t.string "nickname")
  end

  def test_prepare_keeps_a_single_native_action
    # arrange
    # act
    actions = @rake["db:prepare"].actions.size

    # assert
    assert_equal 2, actions
  end
end
