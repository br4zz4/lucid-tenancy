require "migration_helper"
require "rake"

class RakeSchemaDumpTest < MigrationTenancyTest
  RAKEFILE = File.expand_path("../../../lib/tasks/lucid_tenancy.rake", __dir__)
  ADD_NICKNAME = "add_column :students, :nickname, :string".freeze

  def setup
    super
    prepare_template
    @calls = []
    @rake = Rake::Application.new
    Rake.application = @rake
    Rake::Task.define_task("db:load_config")
    load RAKEFILE
    @original_paths = ActiveRecord::Base.connection_pool.migration_context.instance_variable_get(:@migrations_paths)
    ActiveRecord::Migrator.migrations_paths = [@migrations_dir]
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
  end

  def teardown
    ActiveRecord::Migrator.migrations_paths = @original_paths || ["db/migrate"]
    Rake.application = Rake::Application.new
    super
  end

  def define_dump(name)
    calls = @calls
    Rake::Task.define_task(name) { calls << name }
  end

  def invoke(name)
    silence { capture { @rake[name].invoke } }
  end

  def capture
    out = StringIO.new
    original = $stdout
    $stdout = out
    yield
    out.string
  ensure
    $stdout = original
  end

  def test_migrate_invokes_only_the_primary_dump_when_both_exist
    # arrange
    define_dump("db:schema:dump")
    define_dump("db:schema:dump:primary")

    # act
    invoke("lucid:tenancy:migrate")

    # assert
    assert_equal ["db:schema:dump:primary"], @calls
  end

  def test_rollback_invokes_only_the_primary_dump_when_both_exist
    # arrange
    invoke("lucid:tenancy:migrate")
    define_dump("db:schema:dump")
    define_dump("db:schema:dump:primary")

    # act
    invoke("lucid:tenancy:rollback")

    # assert
    assert_equal ["db:schema:dump:primary"], @calls
  end

  def test_migrate_falls_back_to_the_generic_dump
    # arrange
    define_dump("db:schema:dump")

    # act
    invoke("lucid:tenancy:migrate")

    # assert
    assert_equal ["db:schema:dump"], @calls
  end

  def test_rollback_falls_back_to_the_generic_dump
    # arrange
    invoke("lucid:tenancy:migrate")
    define_dump("db:schema:dump")

    # act
    invoke("lucid:tenancy:rollback")

    # assert
    assert_equal ["db:schema:dump"], @calls
  end

  def test_migrate_without_any_dump_task_does_not_fail
    # act
    invoke("lucid:tenancy:migrate")

    # assert
    assert_includes versions("alfa"), "20260101000001"
    assert_empty @calls
  end

  def test_rollback_without_any_dump_task_does_not_fail
    # arrange
    invoke("lucid:tenancy:migrate")

    # act
    invoke("lucid:tenancy:rollback")

    # assert
    refute_includes versions("alfa"), "20260101000001"
    assert_empty @calls
  end
end
