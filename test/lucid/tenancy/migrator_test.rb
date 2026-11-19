require "migration_helper"

class MigratorTest < MigrationTenancyTest
  ADD_NICKNAME = "add_column :students, :nickname, :string".freeze
  ADD_AGE = "add_column :students, :age, :integer".freeze
  CREATE_THINGS = "create_table(:things) { |t| t.string :label }".freeze

  def setup
    super
    prepare_template
  end

  def test_tenant_migration_runs_in_every_tenant_and_the_template
    # arrange
    provision_all("alfa", "beta")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    migrate

    # assert
    %w[alfa beta tt_template].each do |schema|
      assert_includes columns(schema, "students"), "nickname", schema
      assert_includes versions(schema), "20260101000001", schema
    end
  end

  def test_tenant_migration_does_not_touch_the_shared_schema
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    migrate

    # assert
    refute_includes versions("public"), "20260101000001"
    refute_includes tables("public"), "students"
  end

  def test_second_migrate_repeats_nothing
    # arrange
    provision_all("alfa", "beta")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate
    before = %w[alfa beta tt_template public].to_h { |schema| [schema, versions(schema)] }

    # act
    migrate
    after = %w[alfa beta tt_template public].to_h { |schema| [schema, versions(schema)] }

    # assert
    assert_equal before, after
  end

  def test_new_migration_runs_only_where_pending
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate
    write_migration("20260101000002", "add_age", mode: :tenant, body: ADD_AGE)

    # act
    migrate

    # assert
    assert_includes columns("alfa", "students"), "age"
    assert_equal %w[20260101000001 20260101000002], versions("alfa") & %w[20260101000001 20260101000002]
  end

  def test_shared_migration_runs_once_in_the_shared_schema
    # arrange
    provision_all("alfa", "beta")
    write_migration("20260101000001", "create_things", mode: :shared, body: CREATE_THINGS)

    # act
    migrate

    # assert
    assert_includes tables("public"), "things"
    %w[alfa beta tt_template].each do |schema|
      refute_includes tables(schema), "things", schema
      refute_includes versions(schema), "20260101000001", schema
    end
    assert_includes versions("public"), "20260101000001"
  end

  def test_shared_migration_is_not_repeated
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "create_things", mode: :shared, body: CREATE_THINGS)
    migrate

    # act
    migrate

    # assert
    assert_equal 1, versions("public").count("20260101000001")
  end

  def test_missing_declaration_fails_with_the_file_name
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "create_things", mode: nil, body: CREATE_THINGS)

    # act
    error = assert_raises(Lucid::Tenancy::Error::MissingTenancyDeclaration) { migrate }

    # assert
    assert_match(/20260101000001_create_things\.rb/, error.message)
    assert_match(/tenancy :tenant/, error.message)
  end

  def test_missing_declaration_changes_nothing
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: nil, body: ADD_NICKNAME)

    # act
    assert_raises(Lucid::Tenancy::Error::MissingTenancyDeclaration) { migrate }

    # assert
    refute_includes columns("alfa", "students"), "nickname"
  end

  def test_tenant_provisioned_from_a_dump_written_after_migrate_has_the_column
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate
    path = File.join(@migrations_dir, "tenant_schema.rb")
    Lucid::Tenancy::SchemaDump.write(path)
    Lucid::Tenancy.configuration.tenant_schema_path = path

    # act
    tenant = provision_tenant(@klass, "gama")

    # assert
    assert_includes columns(tenant.schema_name, "students"), "nickname"
    assert_equal %w[enrollments notes students], tables("gama") - %w[ar_internal_metadata schema_migrations]
  end

  def test_rollback_undoes_the_last_migration_in_every_tenant_and_template
    # arrange
    provision_all("alfa", "beta")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    write_migration("20260101000002", "add_age", mode: :tenant, body: ADD_AGE)
    migrate

    # act
    rollback(steps: 1)

    # assert
    %w[alfa beta tt_template].each do |schema|
      refute_includes columns(schema, "students"), "age", schema
      assert_includes columns(schema, "students"), "nickname", schema
      refute_includes versions(schema), "20260101000002", schema
      assert_includes versions(schema), "20260101000001", schema
    end
  end

  def test_migrate_never_drops_existing_data_or_tables
    # arrange
    provision_all("alfa")
    connection.execute(%(INSERT INTO "alfa".students (name) VALUES ('Maria'), ('Joao')))
    connection.execute(%(CREATE TABLE "alfa".extra_notes (id serial PRIMARY KEY, body text)))
    connection.execute(%(INSERT INTO "alfa".extra_notes (body) VALUES ('keep me')))
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    migrate

    # assert
    assert_equal %w[Joao Maria], connection.select_values(%(SELECT name FROM "alfa".students ORDER BY name))
    assert_equal ["keep me"], connection.select_values(%(SELECT body FROM "alfa".extra_notes))
  end

  def test_migrate_works_for_a_tenant_with_few_tables
    # arrange
    tenant = create_tenant_schema("sparse")
    @klass.create!(subdomain: tenant.schema_name)
    connection.execute(%(INSERT INTO "#{tenant.schema_name}".students (name) VALUES ('Ana')))
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    migrate

    # assert
    assert_includes columns(tenant.schema_name, "students"), "nickname"
    assert_equal ["Ana"], connection.select_values(%(SELECT name FROM "#{tenant.schema_name}".students))
  end

  def test_pending_lists_versions_per_schema
    # arrange
    provision_all("alfa", "beta")
    write_migration("20260101000001", "create_things", mode: :shared, body: CREATE_THINGS)
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    pending = migrator.pending(paths: [@migrations_dir])

    # assert
    assert_equal [20260101000001], pending["public"]
    %w[tt_template alfa beta].each { |schema| assert_equal [20260101000002], pending[schema], schema }
  end

  def test_pending_is_empty_after_migrate
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "create_things", mode: :shared, body: CREATE_THINGS)
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate

    # act
    pending = migrator.pending(paths: [@migrations_dir])

    # assert
    assert_equal({ "public" => [], "tt_template" => [], "alfa" => [] }, pending)
  end

  def test_tenant_migration_is_applied_to_template_and_both_tenants_with_own_versions
    # arrange
    provision_all("alfa", "beta")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    migrate

    # assert
    %w[tt_template alfa beta].each do |schema|
      assert_includes columns(schema, "students"), "nickname", schema
      assert_includes versions(schema), "20260101000001", schema
    end
    refute_includes versions("public"), "20260101000001"
  end

  def test_pending_is_up_to_date_then_lists_a_new_migration_in_all_three_schemas
    # arrange
    provision_all("alfa", "beta")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate
    up_to_date = migrator.pending(paths: [@migrations_dir])
    write_migration("20260101000002", "add_age", mode: :tenant, body: ADD_AGE)

    # act
    pending = migrator.pending(paths: [@migrations_dir])

    # assert
    assert_equal({ "public" => [], "tt_template" => [], "alfa" => [], "beta" => [] }, up_to_date)
    %w[tt_template alfa beta].each { |schema| assert_equal [20260101000002], pending[schema], schema }
    assert_equal [], pending["public"]
  end

  def test_rollback_removes_the_column_and_the_version_in_all_three_schemas
    # arrange
    provision_all("alfa", "beta")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate

    # act
    rollback(steps: 1)

    # assert
    %w[tt_template alfa beta].each do |schema|
      refute_includes columns(schema, "students"), "nickname", schema
      refute_includes versions(schema), "20260101000001", schema
    end
  end

  def test_ensure_migration_tables_is_idempotent_and_keeps_existing_data
    # arrange
    provision_all("alfa")
    connection.execute(%(INSERT INTO "alfa".schema_migrations (version) VALUES ('20250101000001')))
    connection.execute(%(INSERT INTO "alfa".ar_internal_metadata (key, value, created_at, updated_at) VALUES ('k', 'v', now(), now())))

    # act
    before = versions("alfa")
    2.times { Lucid::Tenancy::Schema.ensure_migration_tables("alfa") }

    # assert
    assert_includes before, "20250101000001"
    assert_equal before, versions("alfa")
    assert_equal ["v"], connection.select_values(%(SELECT value FROM "alfa".ar_internal_metadata WHERE key = 'k'))
  end

  def test_tenant_created_before_migration_tables_existed_is_repaired_without_losing_data
    # arrange
    provision_all("alfa", "beta")
    connection.execute(%(INSERT INTO "alfa".students (name) VALUES ('Maria')))
    connection.execute(%(DROP TABLE "alfa".schema_migrations))
    connection.execute(%(DROP TABLE "alfa".ar_internal_metadata))
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    migrate

    # assert
    assert_includes columns("alfa", "students"), "nickname"
    assert_includes versions("alfa"), "20260101000001"
    assert_includes columns("beta", "students"), "nickname"
    assert_equal ["Maria"], connection.select_values(%(SELECT name FROM "alfa".students))
  end

  def test_migrate_restores_the_search_path
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    migrate

    # assert
    assert_equal "public", connection.select_value("SHOW search_path").delete('"')
  end
end
