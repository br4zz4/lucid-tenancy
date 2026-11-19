require "test_helper"

class TenantTest < TenancyTest
  Error = Lucid::Tenancy::Error

  def test_concern_makes_model_shared
    # arrange
    klass = define_tenant_model

    # assert
    assert klass.shared_table?
    assert_equal "public.tt_organizations", klass.table_name
  end

  def test_schema_name_normalizes_identifier
    # arrange
    klass = define_tenant_model

    # act
    tenant = klass.new(subdomain: "Escola-Alfa")

    # assert
    assert_equal "escola_alfa", tenant.schema_name
  end

  def test_valid_identifier_passes_validation
    # arrange
    klass = define_tenant_model

    # act
    tenant = klass.new(subdomain: "escola-alfa")

    # assert
    assert tenant.valid?
  end

  def test_invalid_identifier_adds_error
    # arrange
    klass = define_tenant_model
    tenant = klass.new(subdomain: "1 bad;drop")

    # act
    valid = tenant.valid?

    # assert
    refute valid
    assert tenant.errors[:subdomain].any?
    assert_raises(Error::InvalidIdentifier) { tenant.schema_name }
  end

  def test_reserved_identifier_adds_error
    # arrange
    klass = define_tenant_model
    reserved = %w[public information_schema pg_catalog].map { |name| klass.new(subdomain: name) }

    # act
    results = reserved.map(&:valid?)

    # assert
    assert_equal [false, false, false], results
    assert(reserved.all? { |tenant| tenant.errors[:subdomain].any? })
    assert_raises(Error::ReservedIdentifier) { reserved.first.schema_name }
  end

  def test_template_schema_is_reserved
    # arrange
    klass = define_tenant_model
    tenant = klass.new(subdomain: Lucid::Tenancy.configuration.template_schema)

    # act
    valid = tenant.valid?

    # assert
    refute valid
  end

  def test_blank_identifier_adds_error
    # arrange
    klass = define_tenant_model
    blank = [klass.new(subdomain: ""), klass.new(subdomain: nil)]

    # act
    results = blank.map(&:valid?)

    # assert
    assert_equal [false, false], results
    assert(blank.all? { |tenant| tenant.errors[:subdomain].any? })
  end

  def test_identifier_cannot_change_after_creation
    # arrange
    klass = define_tenant_model
    tenant = klass.create!(subdomain: "alfa")

    # act
    tenant.subdomain = "beta"
    valid = tenant.valid?

    # assert
    refute valid
    assert_includes tenant.errors[:subdomain], "cannot be changed after creation"
  end

  def test_other_attributes_can_change_after_creation
    # arrange
    klass = define_tenant_model
    tenant = klass.create!(subdomain: "alfa")

    # act
    saved = tenant.save

    # assert
    assert saved
    assert_equal "alfa", klass.find(tenant.id).subdomain
  end

  def test_provision_and_drop_delegate_to_tenancy
    # arrange
    klass = define_tenant_model
    tenant = klass.new(subdomain: "alfa")
    calls = []
    originals = %i[provision drop].to_h { |name| [name, Lucid::Tenancy.method(name)] }
    Lucid::Tenancy.define_singleton_method(:provision) { |arg| calls << [:provision, arg] }
    Lucid::Tenancy.define_singleton_method(:drop) { |arg| calls << [:drop, arg] }

    # act
    begin
      tenant.provision
      tenant.drop
    ensure
      originals.each { |name, original| Lucid::Tenancy.define_singleton_method(name, original.unbind) }
    end

    # assert
    assert_equal [[:provision, tenant], [:drop, tenant]], calls
  end

  def test_tenant_identifier_getter_defaults_to_configuration
    # arrange
    klass = define_tenant_model

    # assert
    assert_equal :subdomain, klass.tenant_identifier
  end

  def test_tenant_identifier_setter_overrides_default
    # arrange
    connection.execute("ALTER TABLE public.tt_organizations ADD COLUMN slug text")
    klass = define_tenant_model
    klass.reset_column_information

    # act
    klass.tenant_identifier :slug
    tenant = klass.new(slug: "Escola-Beta")

    # assert
    assert_equal :slug, klass.tenant_identifier
    assert_equal "escola_beta", tenant.schema_name
  end

  def test_tenant_model_configuration_includes_concern_by_itself
    # arrange
    klass = define_test_class("TtOrganization")
    Lucid::Tenancy.configure { |config| config.tenant_model = "TtOrganization" }

    # act
    resolved = Lucid::Tenancy.tenant_class

    # assert
    assert_same klass, resolved
    assert_operator klass, :<, Lucid::Tenancy::Tenant
    assert_equal "public.tt_organizations", klass.table_name
    assert_equal "escola_alfa", klass.new(subdomain: "escola-alfa").schema_name
  end

  def test_tenant_class_from_concern_without_configuration
    # arrange
    klass = define_tenant_model

    # act
    resolved = Lucid::Tenancy.tenant_class

    # assert
    assert_same klass, resolved
  end

  def test_declaration_in_both_places_with_same_values_works
    # arrange
    Lucid::Tenancy.configure do |config|
      config.tenant_model = "TtOrganization"
      config.tenant_identifier = :subdomain
    end

    # act
    klass = define_tenant_model(identifier: :subdomain)

    # assert
    assert_same klass, Lucid::Tenancy.tenant_class
    assert_equal :subdomain, klass.tenant_identifier
  end

  def test_configured_model_different_from_including_class_conflicts
    # arrange
    Lucid::Tenancy.configure { |config| config.tenant_model = "TtOrganization" }
    other = define_test_class("TtOther")

    # act & assert
    assert_raises(Error::ConfigurationConflict) { other.include(Lucid::Tenancy::Tenant) }
  end

  def test_two_different_classes_including_concern_conflict
    # arrange
    define_tenant_model("TtOrganization")
    other = define_test_class("TtOther")

    # act & assert
    assert_raises(Error::ConfigurationConflict) { other.include(Lucid::Tenancy::Tenant) }
  end

  def test_configured_identifier_different_from_model_declaration_conflicts
    # arrange
    Lucid::Tenancy.configure { |config| config.tenant_identifier = :slug }
    klass = define_tenant_model

    # act & assert
    assert_raises(Error::ConfigurationConflict) { klass.tenant_identifier :subdomain }
  end

  def test_without_tenant_model_raises_not_found
    # act & assert
    assert_raises(Error::TenantNotFound) { Lucid::Tenancy.tenant_class }
  end
end
