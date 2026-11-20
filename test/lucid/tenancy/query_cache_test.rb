require "migration_helper"

class QueryCacheTest < MigrationTenancyTest
  ADD_NICKNAME = "add_column :students, :nickname, :string".freeze
  NAMES_SQL = "SELECT name FROM students ORDER BY name".freeze

  def setup
    super
    prepare_template
    @alfa, @beta = provision_all("alfa", "beta")
    insert_student(@alfa, "ana")
    insert_student(@beta, "bia")
    connection.execute("DROP TABLE IF EXISTS public.students")
    connection.execute("CREATE TABLE public.students (id serial PRIMARY KEY, name text)")
    connection.execute("INSERT INTO public.students (name) VALUES ('shared')")
  end

  def teardown
    connection.execute("DROP TABLE IF EXISTS public.students")
    super
  end

  def names
    ActiveRecord::Base.connection.select_values(NAMES_SQL)
  end

  def test_same_query_in_two_tenants_returns_each_tenants_data
    # arrange
    alfa = @alfa
    beta = @beta

    # act
    result = ActiveRecord::Base.cache do
      [Lucid::Tenancy.with(tenant: alfa) { names }, Lucid::Tenancy.with(tenant: beta) { names }]
    end

    # assert
    assert_equal [["ana"], ["bia"]], result
  end

  def test_going_back_to_the_previous_tenant_reads_its_own_data
    # arrange
    alfa = @alfa
    beta = @beta

    # act
    result = ActiveRecord::Base.cache do
      [
        Lucid::Tenancy.with(tenant: alfa) { names },
        Lucid::Tenancy.with(tenant: beta) { names },
        Lucid::Tenancy.with(tenant: alfa) { names }
      ]
    end

    # assert
    assert_equal [["ana"], ["bia"], ["ana"]], result
  end

  def test_lucid_tenancy_each_yields_each_tenants_data
    # arrange
    collected = []

    # act
    ActiveRecord::Base.cache { Lucid::Tenancy.each { |_tenant| collected << names } }

    # assert
    assert_equal [["ana"], ["bia"]], collected.sort
  end

  def test_shared_and_tenant_read_their_own_tables
    # arrange
    alfa = @alfa

    # act
    result = ActiveRecord::Base.cache do
      [Lucid::Tenancy.shared { names }, Lucid::Tenancy.with(tenant: alfa) { names }, Lucid::Tenancy.shared { names }]
    end

    # assert
    assert_equal [["shared"], ["ana"], ["shared"]], result
  end

  def test_model_pluck_returns_each_tenants_data
    # arrange
    model = define_test_class("TtStudent", table_name: "students")
    alfa = @alfa
    beta = @beta

    # act
    result = ActiveRecord::Base.cache do
      [Lucid::Tenancy.with(tenant: alfa) { model.pluck(:name) }, Lucid::Tenancy.with(tenant: beta) { model.pluck(:name) }]
    end

    # assert
    assert_equal [["ana"], ["bia"]], result
  end

  def test_pending_with_query_cache_matches_pending_without_cache
    # arrange
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate
    write_migration("20260101000002", "add_age", mode: :tenant, body: "add_column :students, :age, :integer")
    expected = migrator.pending(paths: [@migrations_dir])

    # act
    cached = ActiveRecord::Base.cache { migrator.pending(paths: [@migrations_dir]) }

    # assert
    assert_equal expected, cached
    %w[tt_template alfa beta].each { |schema| assert_equal [20260101000002], cached[schema], schema }
  end

  def test_pending_with_query_cache_sees_each_schemas_applied_versions
    # arrange
    write_migration("20260101000001", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate
    expected = migrator.pending(paths: [@migrations_dir])

    # act
    cached = ActiveRecord::Base.cache { migrator.pending(paths: [@migrations_dir]) }

    # assert
    assert_equal expected, cached
    cached.each_value { |versions| assert_empty versions }
  end
end
