require "test_helper"

class SwitchingTest < TenancyTest
  Error = Lucid::Tenancy::Error

  def test_with_returns_block_value_and_restores
    # arrange
    tenant = create_tenant_schema("alfa")

    # act
    result = Lucid::Tenancy.with(tenant: tenant) { [current_schema, 42] }

    # assert
    assert_equal ["tt_alfa", 42], result
    assert_equal "public", current_schema
    assert_nil Lucid::Tenancy.current
  end

  def test_with_restores_on_exception_and_re_raises
    # arrange
    tenant = create_tenant_schema("alfa")

    # act
    error = assert_raises(RuntimeError) do
      Lucid::Tenancy.with(tenant: tenant) { raise "boom" }
    end

    # assert
    assert_equal "boom", error.message
    assert_equal "public", current_schema
    assert_nil Lucid::Tenancy.current
  end

  def test_nested_with_restores_each_level
    # arrange
    alfa = create_tenant_schema("alfa")
    beta = create_tenant_schema("beta")
    seen = []

    # act
    Lucid::Tenancy.with(tenant: alfa) do
      seen << current_schema
      Lucid::Tenancy.with(tenant: beta) { seen << current_schema }
      seen << current_schema
    end
    seen << current_schema

    # assert
    assert_equal %w[tt_alfa tt_beta tt_alfa public], seen
  end

  def test_with_without_block_raises_argument_error
    # arrange
    tenant = create_tenant_schema("alfa")

    # act & assert
    assert_raises(ArgumentError) { Lucid::Tenancy.with(tenant: tenant) }
    assert_nil Lucid::Tenancy.current
    assert_equal "public", current_schema
  end

  def test_shared_block_runs_in_shared_schema_and_restores_tenant
    # arrange
    tenant = create_tenant_schema("alfa")
    Lucid::Tenancy.set(tenant: tenant)

    # act
    inside = Lucid::Tenancy.shared { [current_schema, Lucid::Tenancy.current_scope] }

    # assert
    assert_equal ["public", :shared], inside
    assert_equal "tt_alfa", current_schema
    assert_same tenant, Lucid::Tenancy.current
  end

  def test_with_nil_tenant_is_shared
    # arrange
    tenant = create_tenant_schema("alfa")
    Lucid::Tenancy.set(tenant: tenant)

    # act
    inside = Lucid::Tenancy.with(tenant: nil) { current_schema }

    # assert
    assert_equal "public", inside
    assert_equal "tt_alfa", current_schema
  end

  def test_shared_without_block_raises
    # act & assert
    assert_raises(ArgumentError) { Lucid::Tenancy.shared }
  end

  def test_set_persists_and_exposes_current
    # arrange
    tenant = create_tenant_schema("alfa")

    # act
    returned = Lucid::Tenancy.set(tenant: tenant)

    # assert
    assert_same tenant, returned
    assert_same tenant, Lucid::Tenancy.current
    assert_equal :tenant, Lucid::Tenancy.current_scope
    assert_equal "tt_alfa", current_schema
  end

  def test_current_scope_is_shared_by_default
    # assert
    assert_nil Lucid::Tenancy.current
    assert_equal :shared, Lucid::Tenancy.current_scope
  end

  def test_set_nil_goes_back_to_shared
    # arrange
    tenant = create_tenant_schema("alfa")
    Lucid::Tenancy.set(tenant: tenant)

    # act
    Lucid::Tenancy.set(tenant: nil)

    # assert
    assert_nil Lucid::Tenancy.current
    assert_equal :shared, Lucid::Tenancy.current_scope
    assert_equal "public", current_schema
  end

  def test_set_with_block_behaves_like_with
    # arrange
    tenant = create_tenant_schema("alfa")

    # act
    result = Lucid::Tenancy.set(tenant: tenant) { current_schema }

    # assert
    assert_equal "tt_alfa", result
    assert_nil Lucid::Tenancy.current
    assert_equal "public", current_schema
  end

  def test_string_tenant_without_tenant_model_raises_not_found
    # act & assert
    assert_raises(Error::TenantNotFound) { Lucid::Tenancy.with(tenant: "alfa") { flunk } }
    assert_raises(Error::TenantNotFound) { Lucid::Tenancy.set(tenant: :alfa) }
    assert_nil Lucid::Tenancy.current
  end

  def test_string_tenant_resolved_through_tenant_model
    # arrange
    tenant = create_tenant_schema("alfa")
    finder = Class.new do
      define_singleton_method(:find_by_tenancy_identifier) { |id| id.to_s == "alfa" ? tenant : nil }
    end
    Object.const_set(:TtTenantFinder, finder)
    Lucid::Tenancy.configure { |config| config.tenant_model = "TtTenantFinder" }

    # act
    inside = Lucid::Tenancy.with(tenant: "alfa") { current_schema }

    # assert
    assert_equal "tt_alfa", inside
    assert_raises(Error::TenantNotFound) { Lucid::Tenancy.with(tenant: "zzz") { flunk } }
  ensure
    Object.send(:remove_const, :TtTenantFinder) if Object.const_defined?(:TtTenantFinder)
  end

  def test_threads_see_their_own_tenant_simultaneously
    # arrange
    alfa = create_tenant_schema("alfa")
    beta = create_tenant_schema("beta")
    insert_student(alfa, "Ana")
    insert_student(beta, "Bia")
    insert_student(beta, "Bob")
    barrier = Queue.new
    release = Queue.new
    results = Queue.new
    students = Class.new(ActiveRecord::Base) { self.table_name = "students" }

    run = lambda do |tenant|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Lucid::Tenancy.with(tenant: tenant) do
            barrier << true
            release.pop
            results << [tenant.schema_name, current_schema(ActiveRecord::Base.lease_connection), students.count]
          end
        end
      end
    end

    # act
    threads = [run.call(alfa), run.call(beta)]
    2.times { barrier.pop }
    2.times { release << true }
    threads.each(&:join)
    found = Array.new(2) { results.pop }.to_h { |schema, current, count| [schema, [current, count]] }

    # assert
    assert_equal({ "tt_alfa" => ["tt_alfa", 1], "tt_beta" => ["tt_beta", 2] }, found)
    assert_nil Lucid::Tenancy.current
  end

  def test_released_connection_returns_to_shared_and_next_user_does_not_inherit
    # arrange
    tenant = create_tenant_schema("alfa")
    pool = ActiveRecord::Base.connection_pool
    holder = Thread.new do
      pool.with_connection do |conn|
        Lucid::Tenancy.set(tenant: tenant)
        conn
      end
    end
    used = holder.value

    # act
    held = []
    held << pool.checkout until held.include?(used)
    schema = current_schema(used)
    held.each { |conn| pool.checkin(conn) }

    # assert
    assert_equal "public", schema
  end

  def test_release_connection_resets_to_shared_while_tenant_state_stays
    # arrange
    tenant = create_tenant_schema("alfa")
    pool = ActiveRecord::Base.connection_pool
    Lucid::Tenancy.set(tenant: tenant)
    conn = ActiveRecord::Base.lease_connection

    # act
    ActiveRecord::Base.release_connection
    state_after_release = Lucid::Tenancy.current
    Lucid::Tenancy::State.tenant = nil
    held = []
    held << pool.checkout until held.include?(conn)
    schema_while_idle = current_schema(conn)
    held.each { |c| pool.checkin(c) }

    # assert
    assert_same tenant, state_after_release
    assert_equal "public", schema_while_idle
  end

  def test_re_leasing_on_same_thread_reapplies_current_tenant
    # arrange
    tenant = create_tenant_schema("alfa")
    Lucid::Tenancy.set(tenant: tenant)

    # act
    ActiveRecord::Base.release_connection
    schema = current_schema(ActiveRecord::Base.lease_connection)

    # assert
    assert_equal "tt_alfa", schema
    assert_same tenant, Lucid::Tenancy.current
  end
end
