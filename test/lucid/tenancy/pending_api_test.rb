require "migration_helper"

class PendingApiTest < MigrationTenancyTest
  CREATE_THINGS = "create_table(:things) { |t| t.string :label }".freeze
  ADD_NICKNAME = "add_column :students, :nickname, :string".freeze

  def setup
    super
    prepare_template
  end

  def test_pending_delegates_to_the_migrator
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "create_things", mode: :shared, body: CREATE_THINGS)
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    pending = Lucid::Tenancy.pending(paths: [@migrations_dir])

    # assert
    assert_equal migrator.pending(paths: [@migrations_dir]), pending
    assert_equal [20260101000001], pending["public"]
    assert_equal [20260101000002], pending["alfa"]
  end

  def test_pending_predicate_is_true_when_any_schema_has_a_pending_version
    # arrange
    provision_all("alfa")
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)

    # act
    result = Lucid::Tenancy.pending?(paths: [@migrations_dir])

    # assert
    assert_equal true, result
  end

  def test_pending_predicate_is_false_when_everything_is_migrated
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "create_things", mode: :shared, body: CREATE_THINGS)
    write_migration("20260101000002", "add_nickname", mode: :tenant, body: ADD_NICKNAME)
    migrate

    # act
    result = Lucid::Tenancy.pending?(paths: [@migrations_dir])

    # assert
    assert_equal false, result
  end

  def test_pending_predicate_is_true_when_only_the_shared_schema_is_behind
    # arrange
    provision_all("alfa")
    write_migration("20260101000001", "create_things", mode: :shared, body: CREATE_THINGS)

    # act
    result = Lucid::Tenancy.pending?(paths: [@migrations_dir])

    # assert
    assert_equal true, result
  end
end
