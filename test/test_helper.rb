require "lucid/tenancy"
require "minitest/autorun"

ActiveRecord::Base.establish_connection(ENV.fetch("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/lucid_tenancy_test"))

FakeTenant = Struct.new(:schema_name)

require "tmpdir"

class TenancyTest < Minitest::Test
  VALID_DUMP = <<~RUBY.freeze
    ActiveRecord::Schema[7.2].define(version: 3) do
      create_table :students do |t|
        t.string :name
      end

      create_table :enrollments do |t|
        t.bigint :student_id, null: false
        t.string :code, null: false
        t.index :code, unique: true
      end
      add_foreign_key :enrollments, :students

      create_table :notes do |t|
        t.text :body
      end
    end
  RUBY

  BROKEN_DUMP = <<~RUBY.freeze
    ActiveRecord::Schema[7.2].define(version: 3) do
      create_table :students do |t|
        t.string :name
      end

      create_table :enrollments do |t|
        t.string :code
      end

      create_table :notes do |t|
        t.column :body, :nonexistent_type
      end
    end
  RUBY

  def setup
    @test_schemas = []
    @test_constants = []
    @test_dirs = []
    Lucid::Tenancy.reset_configuration!
    Lucid::Tenancy::State.tenant = nil
    connection.schema_search_path = '"public"'
    connection.execute("DROP TABLE IF EXISTS public.tt_organizations")
    connection.execute("CREATE TABLE public.tt_organizations (id bigserial PRIMARY KEY, subdomain text UNIQUE)")
  end

  def teardown
    Lucid::Tenancy.reset_configuration!
    Lucid::Tenancy::State.tenant = nil
    connection.schema_search_path = '"public"'
    @test_schemas.each { |schema| connection.execute(%(DROP SCHEMA IF EXISTS "#{schema}" CASCADE)) }
    connection.execute("DROP TABLE IF EXISTS public.tt_organizations")
    @test_constants.each { |name| Object.send(:remove_const, name) if Object.const_defined?(name) }
    @test_dirs.each { |dir| FileUtils.remove_entry(dir) if File.exist?(dir) }
  end

  def define_test_class(name, table_name: "tt_organizations")
    klass = Class.new(ActiveRecord::Base)
    klass.table_name = table_name
    Object.const_set(name, klass)
    @test_constants << name
    klass
  end

  def define_tenant_model(name = "TtOrganization", identifier: nil)
    klass = define_test_class(name)
    klass.include(Lucid::Tenancy::Tenant)
    klass.tenant_identifier(identifier) if identifier
    klass
  end

  def use_dump(content)
    dir = Dir.mktmpdir("tenancy")
    @test_dirs << dir
    path = File.join(dir, "tenant_schema.rb")
    File.write(path, content)
    Lucid::Tenancy.configure { |config| config.tenant_schema_path = path }
    path
  end

  def provision_tenant(klass, subdomain)
    tenant = klass.create!(subdomain: subdomain)
    @test_schemas << tenant.schema_name
    tenant.provision
    tenant
  end

  def connection
    ActiveRecord::Base.lease_connection
  end

  def create_tenant_schema(name)
    schema = "tt_#{name}"
    @test_schemas << schema
    connection.execute(%(DROP SCHEMA IF EXISTS "#{schema}" CASCADE))
    connection.execute(%(CREATE SCHEMA "#{schema}"))
    connection.execute(%(CREATE TABLE "#{schema}".students (id serial PRIMARY KEY, name text)))
    FakeTenant.new(schema)
  end

  def current_schema(conn = connection)
    conn.select_value("SELECT current_schema()")
  end

  def insert_student(tenant, name)
    connection.execute(%(INSERT INTO "#{tenant.schema_name}".students (name) VALUES ('#{name}')))
  end
end
