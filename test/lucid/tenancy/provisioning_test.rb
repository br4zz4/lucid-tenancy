require "test_helper"

class ProvisioningTest < TenancyTest
  Error = Lucid::Tenancy::Error

  def setup
    super
    use_dump(VALID_DUMP)
    @klass = define_tenant_model
  end

  def build_tenant(subdomain)
    @test_schemas << subdomain
    @klass.create!(subdomain: subdomain)
  end

  def schema_exists?(schema)
    connection.select_value("SELECT 1 FROM information_schema.schemata WHERE schema_name = '#{schema}'").present?
  end

  def tables(schema)
    connection.select_values("SELECT table_name FROM information_schema.tables WHERE table_schema = '#{schema}' ORDER BY table_name")
  end

  def search_path
    connection.select_value("SHOW search_path")
  end

  def test_provision_creates_all_tables_of_the_dump
    # arrange
    tenant = build_tenant("alfa")

    # act
    tenant.provision

    # assert
    assert_equal %w[enrollments notes schema_migrations students], tables("alfa") - ["ar_internal_metadata"]
  end

  def test_provision_creates_foreign_keys_inside_the_new_schema
    # arrange
    tenant = build_tenant("alfa")

    # act
    tenant.provision
    rows = connection.select_rows(<<~SQL)
      SELECT c.conrelid::regclass::text, c.confrelid::regclass::text, n.nspname, fn.nspname
      FROM pg_constraint c
      JOIN pg_class r ON r.oid = c.conrelid JOIN pg_namespace n ON n.oid = r.relnamespace
      JOIN pg_class f ON f.oid = c.confrelid JOIN pg_namespace fn ON fn.oid = f.relnamespace
      WHERE c.contype = 'f' AND n.nspname = 'alfa'
    SQL

    # assert
    assert_equal [["alfa.enrollments", "alfa.students", "alfa", "alfa"]], rows
  end

  def test_provision_creates_unique_indexes
    # arrange
    tenant = build_tenant("alfa")

    # act
    tenant.provision
    unique = connection.select_values(
      "SELECT indexdef FROM pg_indexes WHERE schemaname = 'alfa' AND tablename = 'enrollments' AND indexdef LIKE 'CREATE UNIQUE%' AND indexdef LIKE '%(code)'"
    )

    # assert
    assert_equal 1, unique.size
    assert_match(/\(code\)/, unique.first)
  end

  def test_provision_gives_each_schema_its_own_sequences
    # arrange
    alfa = build_tenant("alfa")
    beta = build_tenant("beta")

    # act
    alfa.provision
    beta.provision
    defaults = %w[alfa beta].map do |schema|
      connection.select_value(
        "SELECT column_default FROM information_schema.columns WHERE table_schema = '#{schema}' AND table_name = 'students' AND column_name = 'id'"
      )
    end
    sequences = %w[alfa beta].map { |schema| connection.select_value("SELECT pg_get_serial_sequence('#{schema}.students', 'id')") }
    2.times { connection.execute("INSERT INTO alfa.students (name) VALUES ('x')") }
    connection.execute("INSERT INTO beta.students (name) VALUES ('y')")

    # assert
    assert_equal ["alfa.students_id_seq", "beta.students_id_seq"], sequences
    assert_match(/alfa\.students_id_seq|students_id_seq/, defaults.first)
    refute_match(/beta/, defaults.first)
    refute_match(/alfa/, defaults.last)
    assert_equal [1, 2], connection.select_values("SELECT id FROM alfa.students ORDER BY id")
    assert_equal [1], connection.select_values("SELECT id FROM beta.students")
  end

  def test_notes_table_has_bigserial_id_from_own_schema
    # arrange
    tenant = build_tenant("alfa")

    # act
    tenant.provision
    sequence = connection.select_value("SELECT pg_get_serial_sequence('alfa.notes', 'id')")

    # assert
    assert_equal "alfa.notes_id_seq", sequence
  end

  def test_schema_migrations_has_dump_versions
    # arrange
    tenant = build_tenant("alfa")

    # act
    tenant.provision
    versions = connection.select_values("SELECT version FROM alfa.schema_migrations").map(&:to_i)

    # assert
    assert_includes versions, 3
  end

  def test_provision_records_versions_in_the_tenant_and_not_in_public
    # arrange
    connection.execute("DROP TABLE IF EXISTS public.schema_migrations")
    connection.execute("CREATE TABLE public.schema_migrations (version character varying NOT NULL PRIMARY KEY)")
    tenant = build_tenant("alfa")

    # act
    tenant.provision
    tenant_versions = connection.select_values("SELECT version FROM alfa.schema_migrations")
    public_versions = connection.select_values("SELECT version FROM public.schema_migrations")

    # assert
    assert_includes tenant_versions, "3"
    assert_empty public_versions
  ensure
    connection.execute("DROP TABLE IF EXISTS public.schema_migrations")
    connection.execute("DROP TABLE IF EXISTS public.ar_internal_metadata")
  end

  def test_migrate_right_after_provision_applies_nothing_again
    # arrange
    connection.execute("DROP TABLE IF EXISTS public.schema_migrations")
    Lucid::Tenancy.configure { |config| config.tenant_model = "TtOrganization"; config.template_schema = "tt_template" }
    @test_schemas << "tt_template"
    Lucid::Tenancy::Template.create!
    Lucid::Tenancy::Schema.with_path("tt_template") { Lucid::Tenancy::Provisioner.load_dump(Lucid::Tenancy.configuration.tenant_schema_path) }
    build_tenant("alfa").provision
    dir = Dir.mktmpdir("tenancy_migrations")
    @test_dirs << dir

    # act
    before = connection.select_values("SELECT version FROM alfa.schema_migrations").sort
    Lucid::Tenancy::Migrator.migrate(paths: [dir])
    after = connection.select_values("SELECT version FROM alfa.schema_migrations").sort

    # assert
    assert_equal before, after
  ensure
    connection.execute("DROP SCHEMA IF EXISTS tt_template CASCADE")
    connection.execute("DROP TABLE IF EXISTS public.schema_migrations")
    connection.execute("DROP TABLE IF EXISTS public.ar_internal_metadata")
  end

  def test_provision_returns_tenant_and_restores_search_path
    # arrange
    tenant = build_tenant("alfa")

    # act
    returned = Lucid::Tenancy.provision(tenant)

    # assert
    assert_same tenant, returned
    assert_equal "public", search_path
    assert_equal "public", current_schema
    assert_nil Lucid::Tenancy.current
  end

  def test_provision_twice_raises_already_provisioned_without_changes
    # arrange
    tenant = build_tenant("alfa")
    tenant.provision
    connection.execute("INSERT INTO alfa.students (name) VALUES ('Ana')")

    # act
    assert_raises(Error::AlreadyProvisioned) { tenant.provision }

    # assert
    assert_equal ["Ana"], connection.select_values("SELECT name FROM alfa.students")
    assert_equal %w[enrollments notes schema_migrations students], tables("alfa") - ["ar_internal_metadata"]
  end

  def test_missing_dump_raises_clear_error_and_leaves_nothing
    # arrange
    tenant = build_tenant("alfa")
    Lucid::Tenancy.configure { |config| config.tenant_schema_path = "/nonexistent/tenant_schema.rb" }

    # act
    error = assert_raises(Error::TenantNotFound) { tenant.provision }

    # assert
    assert_match(%r{/nonexistent/tenant_schema.rb}, error.message)
    refute schema_exists?("alfa")
  end

  def test_failure_in_the_middle_leaves_no_schema
    # arrange
    use_dump(BROKEN_DUMP)
    tenant = build_tenant("alfa")

    # act
    assert_raises(ActiveRecord::StatementInvalid) { tenant.provision }

    # assert
    refute schema_exists?("alfa")
    assert_equal "public", search_path
    assert_equal "public", current_schema
  end

  def test_after_provision_hook_runs_inside_tenant_schema
    # arrange
    tenant = build_tenant("alfa")
    seen = []
    Lucid::Tenancy.configure do |config|
      config.after_provision = lambda do |provisioned|
        seen << [provisioned, current_schema, Lucid::Tenancy.current]
        connection.execute("INSERT INTO students (name) VALUES ('seed')")
      end
    end

    # act
    tenant.provision

    # assert
    assert_equal [[tenant, "alfa", tenant]], seen
    assert_equal ["seed"], connection.select_values("SELECT name FROM alfa.students")
    assert_equal "public", current_schema
    assert_nil Lucid::Tenancy.current
  end

  def test_after_provision_not_called_when_dump_fails
    # arrange
    use_dump(BROKEN_DUMP)
    tenant = build_tenant("alfa")
    calls = []
    Lucid::Tenancy.configure { |config| config.after_provision = ->(provisioned) { calls << provisioned } }

    # act
    assert_raises(ActiveRecord::StatementInvalid) { tenant.provision }

    # assert
    assert_empty calls
  end

  def test_drop_removes_schema_and_everything_in_it
    # arrange
    tenant = build_tenant("alfa")
    tenant.provision
    connection.execute("INSERT INTO alfa.students (name) VALUES ('Ana')")

    # act
    returned = tenant.drop

    # assert
    assert_same tenant, returned
    refute schema_exists?("alfa")
    assert_empty tables("alfa")
  end

  def test_drop_of_missing_schema_raises_database_error
    # arrange
    tenant = @klass.create!(subdomain: "ghost")

    # act & assert
    assert_raises(ActiveRecord::StatementInvalid) { Lucid::Tenancy.drop(tenant) }
  end

  def test_provision_after_drop_works_again
    # arrange
    tenant = build_tenant("alfa")
    tenant.provision
    tenant.drop

    # act
    tenant.provision

    # assert
    assert schema_exists?("alfa")
  end
end
