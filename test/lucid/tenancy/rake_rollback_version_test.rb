require "migration_helper"
require "rake"

class RakeRollbackVersionTest < MigrationTenancyTest
  RAKEFILE = File.expand_path("../../../lib/tasks/lucid_tenancy.rake", __dir__)
  ADD_NICKNAME = "add_column :students, :nickname, :string".freeze
  ADD_AGE = "add_column :students, :age, :integer".freeze
  ADD_EMAIL = "add_column :students, :email, :string".freeze

  def setup
    super
    prepare_template
    @original_env = ENV.to_h.slice("VERSION", "STEP")
    ENV.delete("VERSION")
    ENV.delete("STEP")
    @original_dump_flag = ActiveRecord.dump_schema_after_migration
    ActiveRecord.dump_schema_after_migration = false
    @rake = Rake::Application.new
    Rake.application = @rake
    Rake::Task.define_task("db:load_config")
    load RAKEFILE
    @original_paths = ActiveRecord::Base.connection_pool.migration_context.instance_variable_get(:@migrations_paths)
    ActiveRecord::Migrator.migrations_paths = [@migrations_dir]
    provision_all("alfa", "beta")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    write_migration("20260101000002", "add_age", mode: :tenant, body: ADD_AGE)
    write_migration("20260101000003", "add_email", mode: :tenant, body: ADD_EMAIL)
    migrate
  end

  def teardown
    ENV.delete("VERSION")
    ENV.delete("STEP")
    @original_env.each { |key, value| ENV[key] = value }
    ActiveRecord.dump_schema_after_migration = @original_dump_flag
    ActiveRecord::Migrator.migrations_paths = @original_paths || ["db/migrate"]
    Rake.application = Rake::Application.new
    super
  end

  def invoke(name)
    silence { capture_stdout { @rake[name].invoke } }
  end

  def capture_stdout
    out = StringIO.new
    original = $stdout
    $stdout = out
    yield
    out.string
  ensure
    $stdout = original
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

  def test_db_rollback_with_version_reverts_everything_newer_than_it
    # arrange
    ENV["VERSION"] = "20260101000001"

    # act
    invoke("db:rollback")

    # assert
    %w[alfa beta tt_template].each do |schema|
      assert_includes columns(schema, "students"), "nickname", schema
      refute_includes columns(schema, "students"), "age", schema
      refute_includes columns(schema, "students"), "email", schema
    end
  end

  def test_lucid_tenancy_rollback_with_version_reverts_everything_newer_than_it
    # arrange
    ENV["VERSION"] = "20260101000001"

    # act
    invoke("lucid:tenancy:rollback")

    # assert
    %w[alfa beta tt_template].each do |schema|
      assert_includes columns(schema, "students"), "nickname", schema
      refute_includes columns(schema, "students"), "age", schema
      refute_includes columns(schema, "students"), "email", schema
    end
  end

  def test_version_takes_precedence_over_step
    # arrange
    ENV["VERSION"] = "20260101000001"
    ENV["STEP"] = "1"

    # act
    invoke("db:rollback")

    # assert
    refute_includes columns("alfa", "students"), "age"
    refute_includes columns("alfa", "students"), "email"
    assert_includes columns("alfa", "students"), "nickname"
  end

  def test_rollback_without_version_still_uses_step
    # arrange
    ENV["STEP"] = "2"

    # act
    invoke("db:rollback")

    # assert
    assert_includes columns("alfa", "students"), "nickname"
    refute_includes columns("alfa", "students"), "age"
    refute_includes columns("alfa", "students"), "email"
  end

  def test_rollback_without_version_or_step_reverts_one
    # act
    invoke("db:rollback")

    # assert
    assert_includes columns("alfa", "students"), "age"
    refute_includes columns("alfa", "students"), "email"
  end

  def test_db_rollback_with_a_non_numeric_version_aborts_with_a_clear_message
    # arrange
    ENV["VERSION"] = "abc"

    # act
    error = assert_raises(SystemExit) do
      capture_stderr { invoke("db:rollback") }
    end

    # assert
    refute error.success?
    assert_includes columns("alfa", "students"), "email"
  end

  def test_non_numeric_version_message_says_version_must_be_a_number
    # arrange
    ENV["VERSION"] = "abc"
    stderr = StringIO.new
    original = $stderr
    $stderr = stderr

    # act
    begin
      invoke("lucid:tenancy:rollback")
    rescue SystemExit
      nil
    ensure
      $stderr = original
    end

    # assert
    assert_includes stderr.string, "VERSION must be a number"
    assert_includes columns("alfa", "students"), "email"
  end
end
