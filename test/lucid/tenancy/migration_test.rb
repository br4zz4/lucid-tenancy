require "test_helper"

class MigrationTest < TenancyTest
  def define_migration(name, &block)
    klass = Class.new(ActiveRecord::Migration[7.2], &block)
    Object.const_set(name, klass)
    @test_constants << name
    klass
  end

  def test_declares_tenant_mode
    # arrange
    klass = define_migration("TtTenantMigration") { tenancy :tenant }

    # act
    mode = klass.tenancy_mode

    # assert
    assert_equal :tenant, mode
  end

  def test_declares_shared_mode
    # arrange
    klass = define_migration("TtSharedMigration") { tenancy :shared }

    # act
    mode = klass.tenancy_mode

    # assert
    assert_equal :shared, mode
  end

  def test_mode_is_nil_without_declaration
    # arrange
    klass = define_migration("TtUndeclaredMigration")

    # act
    mode = klass.tenancy_mode

    # assert
    assert_nil mode
  end

  def test_invalid_mode_raises_argument_error
    # arrange
    klass = define_migration("TtInvalidMigration")

    # act
    error = assert_raises(ArgumentError) { klass.tenancy :global }

    # assert
    assert_match(/tenant or :shared/, error.message)
    assert_nil klass.tenancy_mode
  end

  def test_subclass_inherits_mode
    # arrange
    parent = define_migration("TtParentMigration") { tenancy :shared }

    # act
    child = Class.new(parent)

    # assert
    assert_equal :shared, child.tenancy_mode
  end

  def test_subclass_can_override_mode_without_changing_parent
    # arrange
    parent = define_migration("TtOverrideParent") { tenancy :shared }

    # act
    child = Class.new(parent) { tenancy :tenant }

    # assert
    assert_equal :tenant, child.tenancy_mode
    assert_equal :shared, parent.tenancy_mode
  end

  def test_modes_do_not_leak_between_siblings
    # arrange
    first = define_migration("TtSiblingOne") { tenancy :shared }

    # act
    second = define_migration("TtSiblingTwo")

    # assert
    assert_equal :shared, first.tenancy_mode
    assert_nil second.tenancy_mode
  end
end
