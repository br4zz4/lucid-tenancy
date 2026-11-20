require "migration_helper"

class RollbackToVersionTest < MigrationTenancyTest
  ADD_NICKNAME = "add_column :students, :nickname, :string".freeze
  ADD_AGE = "add_column :students, :age, :integer".freeze
  ADD_EMAIL = "add_column :students, :email, :string".freeze
  CREATE_THINGS = "create_table(:things) { |t| t.string :label }".freeze
  CREATE_SETTINGS_THINGS = "create_table(:settings_things) { |t| t.string :label }".freeze

  def setup
    super
    prepare_template
  end

  def rollback_to(version, steps: 1)
    silence { migrator.rollback(to: version, steps: steps, paths: [@migrations_dir]) }
  end

  def write_three_tenant_migrations
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    write_migration("20260101000002", "add_age", mode: :tenant, body: ADD_AGE)
    write_migration("20260101000003", "add_email", mode: :tenant, body: ADD_EMAIL)
  end

  def test_rollback_to_a_middle_version_reverts_every_newer_version_in_every_tenant_and_template
    # arrange
    provision_all("alfa", "beta")
    write_three_tenant_migrations
    migrate

    # act
    rollback_to("20260101000001")

    # assert
    %w[alfa beta tt_template].each do |schema|
      assert_includes columns(schema, "students"), "nickname", schema
      refute_includes columns(schema, "students"), "age", schema
      refute_includes columns(schema, "students"), "email", schema
      assert_equal %w[20260101000001], versions(schema) & %w[20260101000001 20260101000002 20260101000003], schema
    end
  end

  def test_rollback_to_the_highest_applied_version_reverts_nothing
    # arrange
    provision_all("alfa")
    write_three_tenant_migrations
    migrate

    # act
    rollback_to("20260101000003")

    # assert
    %w[alfa tt_template].each do |schema|
      assert_includes columns(schema, "students"), "email", schema
      assert_includes versions(schema), "20260101000003", schema
    end
  end

  def test_rollback_to_a_version_below_all_applied_reverts_everything
    # arrange
    provision_all("alfa", "beta")
    write_three_tenant_migrations
    migrate

    # act
    rollback_to("20250101000000")

    # assert
    %w[alfa beta tt_template].each do |schema|
      students = columns(schema, "students")
      refute_includes students, "nickname", schema
      refute_includes students, "age", schema
      refute_includes students, "email", schema
      assert_empty versions(schema) & %w[20260101000001 20260101000002 20260101000003], schema
    end
  end

  def test_rollback_to_a_version_is_inclusive_of_the_target_staying_applied
    # arrange
    provision_all("alfa")
    write_three_tenant_migrations
    migrate

    # act
    rollback_to("20260101000002")

    # assert
    assert_includes columns("alfa", "students"), "age"
    refute_includes columns("alfa", "students"), "email"
    assert_includes versions("alfa"), "20260101000002"
    refute_includes versions("alfa"), "20260101000003"
  end

  def test_rollback_to_a_version_handles_shared_and_tenant_migrations_together
    # arrange
    provision_all("alfa", "beta")
    write_migration("20260101000001", "create_things", mode: :shared, body: CREATE_THINGS)
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    write_migration("20260101000003", "create_settings_things", mode: :shared, body: CREATE_SETTINGS_THINGS)
    write_migration("20260101000004", "add_age", mode: :tenant, body: ADD_AGE)
    migrate

    # act
    rollback_to("20260101000001")

    # assert
    assert_includes tables("public"), "things"
    refute_includes tables("public"), "settings_things"
    assert_equal %w[20260101000001], versions("public")
    %w[alfa beta tt_template].each do |schema|
      refute_includes columns(schema, "students"), "nickname", schema
      refute_includes columns(schema, "students"), "age", schema
    end
  end

  def test_rollback_to_a_tenant_version_keeps_shared_versions_lower_than_the_target
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "create_things", mode: :shared, body: CREATE_THINGS)
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    write_migration("20260101000003", "add_age", mode: :tenant, body: ADD_AGE)
    migrate

    # act
    rollback_to("20260101000002")

    # assert
    assert_includes tables("public"), "things"
    assert_equal %w[20260101000001], versions("public")
    assert_includes columns("alfa", "students"), "nickname"
    refute_includes columns("alfa", "students"), "age"
  end

  def test_to_takes_precedence_over_steps
    # arrange
    provision_all("alfa")
    write_three_tenant_migrations
    migrate

    # act
    rollback_to("20260101000001", steps: 1)

    # assert
    refute_includes columns("alfa", "students"), "age"
    refute_includes columns("alfa", "students"), "email"
    assert_includes columns("alfa", "students"), "nickname"
  end

  def test_steps_without_to_keeps_reverting_only_the_requested_count
    # arrange
    provision_all("alfa")
    write_three_tenant_migrations
    migrate

    # act
    rollback(steps: 2)

    # assert
    assert_includes columns("alfa", "students"), "nickname"
    refute_includes columns("alfa", "students"), "age"
    refute_includes columns("alfa", "students"), "email"
  end

  def test_rollback_to_a_version_only_reverts_in_schemas_where_it_was_applied
    # arrange
    provision_all("alfa")
    write_three_tenant_migrations
    migrate
    connection.execute(%(DELETE FROM "alfa".schema_migrations WHERE version = '20260101000003'))
    connection.execute(%(ALTER TABLE "alfa".students DROP COLUMN email))

    # act
    rollback_to("20260101000001")

    # assert
    refute_includes columns("alfa", "students"), "age"
    refute_includes columns("tt_template", "students"), "email"
    refute_includes columns("tt_template", "students"), "age"
    assert_equal %w[20260101000001], versions("alfa") & %w[20260101000001 20260101000002 20260101000003]
  end
end
