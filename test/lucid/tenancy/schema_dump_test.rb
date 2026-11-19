require "migration_helper"

class SchemaDumpTest < MigrationTenancyTest
  SchemaDump = Lucid::Tenancy::SchemaDump

  def setup
    super
    prepare_template
    @path = File.join(@migrations_dir, "tenant_schema.rb")
  end

  def test_dump_contains_the_template_tables
    # arrange
    # act
    dump = SchemaDump.dump

    # assert
    %w[students enrollments notes].each { |table| assert_includes dump, %(create_table "#{table}") }
  end

  def test_dump_does_not_contain_shared_tables
    # arrange
    connection.execute("CREATE TABLE public.things (id serial PRIMARY KEY)")

    # act
    dump = SchemaDump.dump

    # assert
    refute_includes dump, "things"
    refute_includes dump, "tt_organizations"
  end

  def test_dump_does_not_qualify_table_names_with_the_template_schema
    # arrange
    # act
    dump = SchemaDump.dump

    # assert
    refute_includes dump, "tt_template"
  end

  def test_dump_reflects_template_migrations
    # arrange
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: "add_column :students, :nickname, :string")
    migrate

    # act
    dump = SchemaDump.dump

    # assert
    assert_includes dump, %(t.string "nickname")
  end

  def test_write_creates_the_file_with_the_dump
    # arrange
    # act
    returned = SchemaDump.write(@path)

    # assert
    assert_equal @path, returned
    assert_equal SchemaDump.dump, File.read(@path)
  end

  def test_in_sync_is_false_when_the_file_is_missing
    # arrange
    # act
    in_sync = SchemaDump.in_sync?(@path)

    # assert
    refute in_sync
  end

  def test_in_sync_is_true_right_after_write
    # arrange
    SchemaDump.write(@path)

    # act
    in_sync = SchemaDump.in_sync?(@path)

    # assert
    assert in_sync
  end

  def test_in_sync_is_false_when_the_file_is_outdated
    # arrange
    SchemaDump.write(@path)
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: "add_column :students, :nickname, :string")
    migrate

    # act
    in_sync = SchemaDump.in_sync?(@path)

    # assert
    refute in_sync
  end

  def test_in_sync_is_true_again_after_rewriting
    # arrange
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: "add_column :students, :nickname, :string")
    migrate
    SchemaDump.write(@path)

    # act
    in_sync = SchemaDump.in_sync?(@path)

    # assert
    assert in_sync
  end

  def test_dump_restores_the_search_path
    # arrange
    # act
    SchemaDump.dump

    # assert
    assert_equal "public", connection.select_value("SHOW search_path").delete('"')
  end
end
