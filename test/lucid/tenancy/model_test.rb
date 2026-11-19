require "test_helper"

class ModelTest < TenancyTest
  def setup
    super
    connection.execute("DROP TABLE IF EXISTS public.tt_shared_things")
    connection.execute("CREATE TABLE public.tt_shared_things (id serial PRIMARY KEY, name text)")
  end

  def teardown
    Lucid::Tenancy::State.tenant = nil
    connection.schema_search_path = '"public"'
    connection.execute("DROP TABLE IF EXISTS public.tt_shared_things")
    super
  end

  def build_shared_class
    Class.new(ActiveRecord::Base) do
      def self.name
        "TtSharedThing"
      end

      self.table_name = "tt_shared_things"
      tenancy :shared
    end
  end

  def test_shared_model_uses_shared_schema_table
    # act
    klass = build_shared_class

    # assert
    assert_equal "public.tt_shared_things", klass.table_name
    assert klass.shared_table?
    refute klass.tenant_table?
    assert_equal :shared, klass.tenancy_mode
  end

  def test_shared_model_is_queryable_inside_another_tenant
    # arrange
    klass = build_shared_class
    tenant = create_tenant_schema("alfa")
    klass.create!(name: "global")

    # act
    names = Lucid::Tenancy.with(tenant: tenant) { klass.pluck(:name) }

    # assert
    assert_equal ["global"], names
  end

  def test_tenant_is_default_and_keeps_table_name
    # act
    klass = Class.new(ActiveRecord::Base) { self.table_name = "students" }

    # assert
    assert_equal :tenant, klass.tenancy_mode
    assert klass.tenant_table?
    refute klass.shared_table?
    assert_equal "students", klass.table_name
  end

  def test_explicit_tenant_mode_keeps_table_name
    # act
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "students"
      tenancy :tenant
    end

    # assert
    assert_equal "students", klass.table_name
    assert klass.tenant_table?
  end

  def test_tenant_model_reads_the_current_tenant_schema
    # arrange
    tenant = create_tenant_schema("alfa")
    insert_student(tenant, "Ana")
    klass = Class.new(ActiveRecord::Base) { self.table_name = "students" }

    # act
    names = Lucid::Tenancy.with(tenant: tenant) { klass.pluck(:name) }

    # assert
    assert_equal ["Ana"], names
  end

  def test_invalid_mode_raises
    # act & assert
    assert_raises(ArgumentError) do
      Class.new(ActiveRecord::Base) { tenancy :other }
    end
  end

  def test_subclass_inherits_mode_and_table
    # arrange
    parent = build_shared_class
    child = Class.new(parent)

    # assert
    assert child.shared_table?
    assert_equal :shared, child.tenancy_mode
    assert_equal "public.tt_shared_things", child.table_name
  end

  def test_subclass_of_tenant_model_inherits_tenant_mode
    # arrange
    parent = Class.new(ActiveRecord::Base) { self.table_name = "students" }
    child = Class.new(parent)

    # assert
    assert child.tenant_table?
  end
end
