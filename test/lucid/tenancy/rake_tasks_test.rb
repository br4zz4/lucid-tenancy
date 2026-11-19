require "migration_helper"
require "rake"

class RakeTasksTest < MigrationTenancyTest
  RAKEFILE = File.expand_path("../../../lib/tasks/lucid_tenancy.rake", __dir__)

  def setup
    super
    prepare_template
    @path = Lucid::Tenancy.configuration.tenant_schema_path
    @rake = Rake::Application.new
    Rake.application = @rake
    Rake::Task.define_task("db:load_config")
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

  def test_migrate_task_migrates_every_schema_and_writes_the_dump
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: "add_column :students, :nickname, :string")

    # act
    invoke("lucid:tenancy:migrate")

    # assert
    %w[alfa tt_template].each { |schema| assert_includes columns(schema, "students"), "nickname", schema }
    assert_includes File.read(@path), %(t.string "nickname")
  end

  def test_db_migrate_runs_the_gem_migrate
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: "add_column :students, :nickname, :string")

    # act
    invoke("db:migrate")

    # assert
    assert_includes columns("alfa", "students"), "nickname"
    assert_includes versions("alfa"), "20260101000001"
  end

  def test_db_migrate_depends_only_on_the_gem_tasks
    # arrange
    # act
    prerequisites = @rake["db:migrate"].prerequisites

    # assert
    assert_equal ["db:load_config"], prerequisites
  end

  def test_status_task_prints_pending_per_schema
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: "add_column :students, :nickname, :string")

    # act
    output = capture { silence { @rake["lucid:tenancy:status"].invoke } }

    # assert
    assert_match(/^alfa: 20260101000001$/, output)
    assert_match(/^tt_template: 20260101000001$/, output)
    assert_match(/^public: up to date$/, output)
  end

  def test_db_migrate_status_prints_pending_per_schema
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: "add_column :students, :nickname, :string")

    # act
    output = capture { silence { @rake["db:migrate:status"].invoke } }

    # assert
    assert_match(/^alfa: 20260101000001$/, output)
  end

  %w[up down redo].each do |name|
    define_method("test_db_migrate_#{name}_aborts") do
      # arrange
      stderr = nil

      # act
      error = nil
      stderr = capture_stderr { error = assert_raises(SystemExit) { invoke("db:migrate:#{name}") } }

      # assert
      refute error.success?
      assert_match(/db:migrate:#{name}/, stderr)
    end
  end

  def test_baseline_task_creates_the_version_table_of_one_tenant
    # arrange
    provision_all("alfa")
    connection.execute(%(DROP TABLE "alfa".schema_migrations))

    # act
    output = silence { capture { @rake["lucid:tenancy:baseline"].invoke("alfa") } }

    # assert
    assert_match(/baseline: alfa/, output)
    assert Lucid::Tenancy::Schema.migration_tables?("alfa")
  end

  def test_baseline_task_without_argument_covers_every_tenant
    # arrange
    provision_all("alfa", "beta")
    %w[alfa beta].each { |schema| connection.execute(%(DROP TABLE "#{schema}".schema_migrations)) }

    # act
    invoke("lucid:tenancy:baseline")

    # assert
    %w[alfa beta].each { |schema| assert Lucid::Tenancy::Schema.migration_tables?(schema), schema }
  end

  def test_dump_task_writes_the_template_dump
    # arrange
    # act
    invoke("lucid:tenancy:dump")

    # assert
    assert File.exist?(@path)
    assert_equal Lucid::Tenancy::SchemaDump.dump, File.read(@path)
  end

  def test_dump_task_does_nothing_without_a_template
    # arrange
    connection.execute(%(DROP SCHEMA "#{TEMPLATE}" CASCADE))
    FileUtils.rm_f(@path)

    # act
    invoke("lucid:tenancy:dump")

    # assert
    refute File.exist?(@path)
  end

  def test_check_task_passes_when_in_sync
    # arrange
    Lucid::Tenancy::SchemaDump.write(@path)

    # act
    result = invoke("lucid:tenancy:check")

    # assert
    assert_equal "", result
  end

  def test_check_task_aborts_when_out_of_sync
    # arrange
    File.write(@path, "outdated")

    # act
    error = nil
    stderr = capture_stderr { error = assert_raises(SystemExit) { invoke("lucid:tenancy:check") } }

    # assert
    refute error.success?
    assert_match(/out of date/, stderr)
  end

  def capture_stderr
    out = StringIO.new
    original = $stderr
    $stderr = out
    yield
    out.string
  ensure
    $stderr = original
  end
end
