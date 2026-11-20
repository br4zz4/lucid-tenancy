require "migration_helper"
require "rake"

class RakeSchemaDumpTest < MigrationTenancyTest
  RAKEFILE = File.expand_path("../../../lib/tasks/lucid_tenancy.rake", __dir__)
  ADD_NICKNAME = "add_column :students, :nickname, :string".freeze

  def setup
    super
    prepare_template
    @calls = []
    @original_dump_flag = ActiveRecord.dump_schema_after_migration
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
    ActiveRecord.dump_schema_after_migration = @original_dump_flag
    ActiveRecord::Migrator.migrations_paths = @original_paths || ["db/migrate"]
    Rake.application = Rake::Application.new
    super
  end

  def define_dump(name)
    calls = @calls
    Rake::Task.define_task(name) { calls << name }
  end

  def record_template_dump
    calls = @calls
    task = @rake["lucid:tenancy:dump"]
    task.clear_actions
    task.enhance { calls << "lucid:tenancy:dump" }
    task.reenable
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

  def test_migrate_with_the_flag_on_invokes_the_template_and_primary_dumps
    # arrange
    ActiveRecord.dump_schema_after_migration = true
    record_template_dump
    define_dump("db:schema:dump:primary")

    # act
    invoke("lucid:tenancy:migrate")

    # assert
    assert_equal ["lucid:tenancy:dump", "db:schema:dump:primary"], @calls
  end

  def test_rollback_with_the_flag_on_invokes_the_template_and_primary_dumps
    # arrange
    ActiveRecord.dump_schema_after_migration = true
    invoke("lucid:tenancy:migrate")
    record_template_dump
    define_dump("db:schema:dump:primary")

    # act
    invoke("lucid:tenancy:rollback")

    # assert
    assert_equal ["lucid:tenancy:dump", "db:schema:dump:primary"], @calls
  end

  def test_migrate_with_the_flag_off_migrates_without_any_dump
    # arrange
    ActiveRecord.dump_schema_after_migration = false
    record_template_dump
    define_dump("db:schema:dump:primary")
    define_dump("db:schema:dump")

    # act
    invoke("lucid:tenancy:migrate")

    # assert
    assert_includes columns("alfa", "students"), "nickname"
    assert_includes versions("alfa"), "20260101000001"
    assert_empty @calls
  end

  def test_rollback_with_the_flag_off_rolls_back_without_any_dump
    # arrange
    ActiveRecord.dump_schema_after_migration = false
    invoke("lucid:tenancy:migrate")
    record_template_dump
    define_dump("db:schema:dump:primary")
    define_dump("db:schema:dump")

    # act
    invoke("lucid:tenancy:rollback")

    # assert
    refute_includes columns("alfa", "students"), "nickname"
    refute_includes versions("alfa"), "20260101000001"
    assert_empty @calls
  end

  def test_db_migrate_with_the_flag_off_does_not_write_the_template_dump
    # arrange
    ActiveRecord.dump_schema_after_migration = false
    path = Lucid::Tenancy.configuration.tenant_schema_path
    before = File.read(path)

    # act
    invoke("db:migrate")

    # assert
    assert_includes columns("alfa", "students"), "nickname"
    assert_equal before, File.read(path)
  end

  def test_db_migrate_with_the_flag_on_writes_the_template_dump
    # arrange
    ActiveRecord.dump_schema_after_migration = true
    path = Lucid::Tenancy.configuration.tenant_schema_path

    # act
    invoke("db:migrate")

    # assert
    assert_includes File.read(path), %(t.string "nickname")
  end

  def test_dump_schemas_invokes_the_template_and_the_primary_dump
    # arrange
    record_template_dump
    define_dump("db:schema:dump:primary")
    define_dump("db:schema:dump")

    # act
    Lucid::Tenancy.dump_schemas

    # assert
    assert_equal ["lucid:tenancy:dump", "db:schema:dump:primary"], @calls
  end

  def test_dump_schemas_falls_back_to_the_generic_dump
    # arrange
    record_template_dump
    define_dump("db:schema:dump")

    # act
    Lucid::Tenancy.dump_schemas

    # assert
    assert_equal ["lucid:tenancy:dump", "db:schema:dump"], @calls
  end
end
