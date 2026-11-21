require "migration_helper"

class HealthTest < MigrationTenancyTest
  ADD_NICKNAME = "add_column :students, :nickname, :string".freeze
  WRITE_PATTERN = /\A\s*(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE)\b/i

  def setup
    super
    prepare_template
  end

  def capture_sql
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    statements
  end

  def test_health_of_a_tenant_in_sync_is_ok
    # arrange
    alfa, = provision_all("alfa")

    # act
    health = Lucid::Tenancy.health(alfa)

    # assert
    assert_instance_of Lucid::Tenancy::Health, health
    assert_equal "alfa", health.schema
    assert health.provisioned?
    assert health.ok?
    assert_empty health.missing_tables
    assert_empty health.extra_tables
    assert_empty health.column_drift
    assert_empty health.pending_versions
  end

  def test_health_reports_missing_and_extra_tables
    # arrange
    alfa, = provision_all("alfa")
    connection.execute(%(DROP TABLE "alfa".notes))
    connection.execute(%(CREATE TABLE "alfa".tmp_x (id serial PRIMARY KEY)))

    # act
    health = Lucid::Tenancy.health(alfa)

    # assert
    assert_equal ["notes"], health.missing_tables
    assert_equal ["tmp_x"], health.extra_tables
    refute health.ok?
  end

  def test_health_reports_column_type_drift_and_missing_columns
    # arrange
    alfa, = provision_all("alfa")
    connection.execute(%(ALTER TABLE "alfa".students ALTER COLUMN name TYPE integer USING NULL))
    connection.execute(%(ALTER TABLE "alfa".enrollments DROP COLUMN code))

    # act
    health = Lucid::Tenancy.health(alfa)
    drift = health.column_drift.sort_by { |entry| [entry.table, entry.column] }

    # assert
    assert(drift.all?(Lucid::Tenancy::Health::ColumnDrift))
    assert_equal(
      [
        { table: "enrollments", column: "code", expected: "character varying", actual: nil },
        { table: "students", column: "name", expected: "character varying", actual: "integer" }
      ],
      drift.map(&:to_h)
    )
    refute health.ok?
  end

  def test_health_ignores_the_migration_bookkeeping_tables
    # arrange
    alfa, = provision_all("alfa")
    connection.execute(%(DROP TABLE IF EXISTS "alfa".ar_internal_metadata))

    # act
    health = Lucid::Tenancy.health(alfa)

    # assert
    assert_empty health.missing_tables
    assert_empty health.extra_tables
    assert health.ok?
  end

  def test_health_reports_pending_versions_of_the_tenant
    # arrange
    alfa, = provision_all("alfa")
    write_migration("20261101000000", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    health = Lucid::Tenancy.health(alfa, paths: [@migrations_dir])

    # assert
    assert_equal [20261101000000], health.pending_versions
    refute health.ok?
  end

  def test_health_collects_every_divergence_together
    # arrange
    alfa, = provision_all("alfa")
    connection.execute(%(DROP TABLE "alfa".notes))
    connection.execute(%(CREATE TABLE "alfa".tmp_x (id serial PRIMARY KEY)))
    connection.execute(%(ALTER TABLE "alfa".students ALTER COLUMN name TYPE integer USING NULL))
    write_migration("20261101000000", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    health = Lucid::Tenancy.health(alfa, paths: [@migrations_dir])

    # assert
    assert health.provisioned?
    refute health.ok?
    assert_equal ["notes"], health.missing_tables
    assert_equal ["tmp_x"], health.extra_tables
    assert_equal [{ table: "students", column: "name", expected: "character varying", actual: "integer" }], health.column_drift.map(&:to_h)
    assert_equal [20261101000000], health.pending_versions
  end

  def test_health_of_a_tenant_without_schema
    # arrange
    ghost = @klass.create!(subdomain: "ghost")
    @test_schemas << ghost.schema_name

    # act
    statements = capture_sql { @health = Lucid::Tenancy.health(ghost) }

    # assert
    refute @health.provisioned?
    refute @health.ok?
    assert_equal "ghost", @health.schema
    assert_empty @health.missing_tables
    assert_empty @health.extra_tables
    assert_empty @health.column_drift
    assert_empty @health.pending_versions
    assert_empty(statements.grep(/information_schema\.columns/i))
  end

  def test_health_only_reads_the_catalog
    # arrange
    alfa, = provision_all("alfa")
    connection.execute(%(DROP TABLE "alfa".notes))
    write_migration("20261101000000", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    statements = capture_sql { Lucid::Tenancy.health(alfa, paths: [@migrations_dir]) }

    # assert
    refute_empty statements
    assert_empty(statements.grep(WRITE_PATTERN))
  end

  def test_health_does_not_change_the_tenant
    # arrange
    alfa, = provision_all("alfa")
    connection.execute(%(INSERT INTO "alfa".students (name) VALUES ('Ana')))
    before = [tables("alfa"), versions("alfa"), connection.select_values(%(SELECT name FROM "alfa".students))]

    # act
    Lucid::Tenancy.health(alfa)
    after = [tables("alfa"), versions("alfa"), connection.select_values(%(SELECT name FROM "alfa".students))]

    # assert
    assert_equal before, after
    assert_equal "public", current_schema
    assert_nil Lucid::Tenancy.current
  end
end
