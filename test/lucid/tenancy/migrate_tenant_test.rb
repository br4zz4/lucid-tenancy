require "migration_helper"

class MigrateTenantTest < MigrationTenancyTest
  CREATE_THINGS = "create_table(:things) { |t| t.string :label }".freeze
  ADD_NICKNAME = "add_column :students, :nickname, :string".freeze
  ADD_AGE = "add_column :students, :age, :integer".freeze

  def setup
    super
    prepare_template
  end

  def test_migrate_runs_pending_tenant_migrations_only_in_that_tenant
    # arrange
    alfa, beta = provision_all("alfa", "beta")
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    write_migration("20260101000003", "add_age", mode: :tenant, body: ADD_AGE)
    beta_versions = versions("beta")
    template_versions = versions(TEMPLATE)

    # act
    silence { Lucid::Tenancy.migrate(alfa, paths: [@migrations_dir]) }

    # assert
    assert_includes columns("alfa", "students"), "nickname"
    assert_includes columns("alfa", "students"), "age"
    assert_includes versions("alfa"), "20260101000002"
    assert_includes versions("alfa"), "20260101000003"
    refute_includes columns("beta", "students"), "nickname"
    refute_includes columns("beta", "students"), "age"
    assert_equal beta_versions, versions("beta")
    refute_includes columns(TEMPLATE, "students"), "nickname"
    assert_equal template_versions, versions(TEMPLATE)
    assert_equal [20260101000002, 20260101000003], Lucid::Tenancy.pending(tenant: beta, paths: [@migrations_dir])
  end

  def test_migrate_does_not_run_shared_migrations
    # arrange
    alfa, = provision_all("alfa")
    write_migration("20260101000001", "create_things", mode: :shared, body: CREATE_THINGS)
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    silence { Lucid::Tenancy.migrate(alfa, paths: [@migrations_dir]) }

    # assert
    assert_empty tables("public") & ["things"]
    refute_includes tables("alfa"), "things"
    refute_includes versions("alfa"), "20260101000001"
    assert_includes versions("alfa"), "20260101000002"
  end

  def test_migrate_leaves_nothing_pending_for_the_tenant
    # arrange
    alfa, = provision_all("alfa")
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    silence { Lucid::Tenancy.migrate(alfa, paths: [@migrations_dir]) }

    # assert
    assert_empty Lucid::Tenancy.pending(tenant: alfa, paths: [@migrations_dir])
    assert_equal "public", current_schema
    assert_nil Lucid::Tenancy.current
  end

  def test_migrate_without_pending_changes_nothing
    # arrange
    alfa, = provision_all("alfa")
    before = [tables("alfa"), versions("alfa")]

    # act
    silence { Lucid::Tenancy.migrate(alfa, paths: [@migrations_dir]) }

    # assert
    assert_equal before, [tables("alfa"), versions("alfa")]
  end

  def test_migrate_a_tenant_without_schema_raises_not_provisioned
    # arrange
    ghost = @klass.create!(subdomain: "ghost")
    @test_schemas << ghost.schema_name
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act & assert
    assert_raises(Lucid::Tenancy::Error::NotProvisioned) do
      silence { Lucid::Tenancy.migrate(ghost, paths: [@migrations_dir]) }
    end
    assert_empty tables("ghost")
    assert_empty connection.select_values("SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'ghost'")
  end
end
