require "test_helper"

class CollectionTest < TenancyTest
  def setup
    super
    use_dump(VALID_DUMP)
    @klass = define_tenant_model
    @tenants = %w[alfa beta gama].map { |name| provision_tenant(@klass, name) }
    @tenants.each do |tenant|
      connection.execute(%(INSERT INTO "#{tenant.schema_name}".students (name) VALUES ('aluno de #{tenant.subdomain}')))
    end
  end

  def student_names
    connection.select_values("SELECT name FROM students")
  end

  def search_path
    connection.select_value("SHOW search_path")
  end

  def test_each_yields_every_tenant_inside_its_schema
    # arrange
    seen = []

    # act
    Lucid::Tenancy.each { |tenant| seen << [tenant.subdomain, current_schema, student_names] }

    # assert
    assert_equal [
      ["alfa", "alfa", ["aluno de alfa"]],
      ["beta", "beta", ["aluno de beta"]],
      ["gama", "gama", ["aluno de gama"]]
    ], seen
  end

  def test_each_restores_schema_and_state
    # act
    Lucid::Tenancy.each { |_tenant| nil }

    # assert
    assert_equal "public", current_schema
    assert_nil Lucid::Tenancy.current
  end

  def test_each_sets_current_tenant_inside_block
    # arrange
    currents = []

    # act
    Lucid::Tenancy.each { |tenant| currents << (Lucid::Tenancy.current == tenant) }

    # assert
    assert_equal [true, true, true], currents
  end

  def test_each_restores_previous_tenant_when_nested_in_one
    # arrange
    outer = @tenants.last

    # act
    inside = Lucid::Tenancy.with(tenant: outer) do
      Lucid::Tenancy.each { |_tenant| nil }
      [current_schema, Lucid::Tenancy.current]
    end

    # assert
    assert_equal ["gama", outer], inside
  end

  def test_each_returns_enumerator_without_block
    # act
    enumerator = Lucid::Tenancy.each

    # assert
    assert_kind_of Enumerator, enumerator
    assert_equal %w[alfa beta gama], enumerator.map(&:subdomain)
    assert_equal "public", current_schema
  end

  def test_map_runs_each_block_in_its_schema
    # act
    counts = Lucid::Tenancy.map { |tenant| [tenant.subdomain, connection.select_value("SELECT count(*) FROM students")] }.to_h

    # assert
    assert_equal({ "alfa" => 1, "beta" => 1, "gama" => 1 }, counts)
    assert_equal "public", current_schema
  end

  def test_find_that_stops_in_the_middle_restores_schema
    # act
    found = Lucid::Tenancy.find { |tenant| tenant.subdomain == "beta" }

    # assert
    assert_equal "beta", found.subdomain
    assert_equal "public", current_schema
    assert_nil Lucid::Tenancy.current
  end

  def test_find_block_runs_inside_tenant_schema
    # act
    found = Lucid::Tenancy.find { |_tenant| student_names == ["aluno de gama"] }

    # assert
    assert_equal "gama", found.subdomain
  end

  def test_exception_in_block_restores_and_re_raises
    # act
    error = assert_raises(RuntimeError) do
      Lucid::Tenancy.each { |tenant| raise "boom #{tenant.subdomain}" if tenant.subdomain == "beta" }
    end

    # assert
    assert_equal "boom beta", error.message
    assert_equal "public", current_schema
    assert_nil Lucid::Tenancy.current
  end

  def test_order_follows_id
    # arrange
    @klass.create!(subdomain: "delta")
    @klass.where(subdomain: "alfa").update_all(subdomain: "zzz")

    # act
    ids = Lucid::Tenancy.to_a.map(&:id)

    # assert
    assert_equal ids.sort, ids
    assert_equal %w[zzz beta gama delta], Lucid::Tenancy.to_a.map(&:subdomain)
  end

  def test_first_returns_lowest_id_tenant_and_restores
    # act
    first = Lucid::Tenancy.first

    # assert
    assert_equal "alfa", first.subdomain
    assert_equal "public", current_schema
  end

  def test_select_filters_with_block_in_each_schema
    # act
    selected = Lucid::Tenancy.select { |tenant| tenant.subdomain != "beta" && student_names.size == 1 }

    # assert
    assert_equal %w[alfa gama], selected.map(&:subdomain)
    assert_equal "public", current_schema
  end

  def test_count_size_and_to_a_do_not_switch_schema
    # arrange
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql] if payload[:sql].match?(/search_path/i)
    end

    # act
    results = [Lucid::Tenancy.count, Lucid::Tenancy.size, Lucid::Tenancy.to_a.size]
    ActiveSupport::Notifications.unsubscribe(subscriber)

    # assert
    assert_equal [3, 3, 3], results
    assert_empty(statements.grep(/"?(alfa|beta|gama)"?/))
    assert_equal "public", search_path
    assert_equal "public", current_schema
  end

  def test_count_inside_a_tenant_leaves_that_tenant_active
    # arrange
    tenant = @tenants.first

    # act
    inside = Lucid::Tenancy.with(tenant: tenant) do
      total = Lucid::Tenancy.count
      [total, current_schema, Lucid::Tenancy.current]
    end

    # assert
    assert_equal [3, "alfa", tenant], inside
  end

  def test_count_with_block_counts_matching_tenants
    # act
    count = Lucid::Tenancy.count { |tenant| tenant.subdomain.start_with?("g") }

    # assert
    assert_equal 1, count
  end
end
