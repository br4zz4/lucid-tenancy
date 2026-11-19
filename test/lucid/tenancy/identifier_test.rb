require "test_helper"

class IdentifierTest < TenancyTest
  Identifier = Lucid::Tenancy::Identifier
  Error = Lucid::Tenancy::Error

  def test_normalizes_hyphen_and_case
    # act
    schema = Identifier.schema_for("Escola-Alfa")

    # assert
    assert_equal "escola_alfa", schema
  end

  def test_accepts_symbol_and_surrounding_spaces
    # assert
    assert_equal "alfa", Identifier.schema_for(:alfa)
    assert_equal "alfa", Identifier.schema_for("  alfa ")
  end

  def test_accepts_maximum_length
    # arrange
    name = "a" * 63

    # assert
    assert_equal name, Identifier.schema_for(name)
  end

  [
    ["empty", ""],
    ["nil", nil],
    ["starting with digit", "1abc"],
    ["single char", "a"],
    ["with space", "esc ola"],
    ["with dot", "esc.ola"],
    ["with semicolon", "abc;"],
    ["accented uppercase", "ÉScola"],
    ["too long", "a" * 64],
    ["with quote", 'ab"c'],
    ["injection", 'a"; drop schema public; --']
  ].each do |label, value|
    define_method("test_invalid_#{label.tr(' ', '_')}") do
      # act & assert
      assert_raises(Error::InvalidIdentifier) { Identifier.schema_for(value) }
      refute Identifier.valid?(value)
    end
  end

  def test_reserved_built_in
    # assert
    ["public", "information_schema", "pg_catalog", "pg_x", "PUBLIC"].each do |name|
      assert_raises(Error::ReservedIdentifier, name) { Identifier.schema_for(name) }
      refute Identifier.valid?(name)
    end
  end

  def test_reserved_template_schema
    # assert
    assert_raises(Error::ReservedIdentifier) { Identifier.schema_for("tenancy_template") }
  end

  def test_reserved_configured_template_and_shared
    # arrange
    Lucid::Tenancy.configure do |config|
      config.template_schema = "my_template"
      config.shared_schema = "my_shared"
    end

    # assert
    assert_raises(Error::ReservedIdentifier) { Identifier.schema_for("my_template") }
    assert_raises(Error::ReservedIdentifier) { Identifier.schema_for("my_shared") }
    assert_equal "tenancy_template", Identifier.schema_for("tenancy_template")
  end

  def test_reserved_custom_string_and_regexp
    # arrange
    Lucid::Tenancy.configure { |config| config.reserved_identifiers = ["admin", /\Asys_/] }

    # assert
    assert_raises(Error::ReservedIdentifier) { Identifier.schema_for("admin") }
    assert_raises(Error::ReservedIdentifier) { Identifier.schema_for("sys_core") }
    assert_equal "administrador", Identifier.schema_for("administrador")
  end

  def test_valid_predicate
    # assert
    assert Identifier.valid?("escola-alfa")
    refute Identifier.valid?("public")
    refute Identifier.valid?("1abc")
  end

  def test_injection_is_refused_before_touching_the_database
    # arrange
    malicious = 'a"; drop schema public; --'

    # act & assert
    assert_raises(Error::InvalidIdentifier) { Identifier.schema_for(malicious) }
    assert_equal 1, connection.select_value("SELECT count(*) FROM information_schema.schemata WHERE schema_name = 'public'")
  end

  def test_search_path_quotes_schema_names
    # arrange
    tenant = FakeTenant.new('we"ird')

    # act
    path = Lucid::Tenancy.search_path_for(tenant, connection)

    # assert
    assert_equal '"we""ird", "public"', path
  end
end
