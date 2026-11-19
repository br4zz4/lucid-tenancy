require "lucid/tenancy"
require "minitest/autorun"

ActiveRecord::Base.establish_connection(ENV.fetch("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/lucid_tenancy_test"))

FakeTenant = Struct.new(:schema_name)

class TenancyTest < Minitest::Test
  def setup
    @test_schemas = []
    Lucid::Tenancy.reset_configuration!
    Lucid::Tenancy::State.tenant = nil
    connection.schema_search_path = '"public"'
  end

  def teardown
    Lucid::Tenancy.reset_configuration!
    Lucid::Tenancy::State.tenant = nil
    connection.schema_search_path = '"public"'
    @test_schemas.each { |schema| connection.execute(%(DROP SCHEMA IF EXISTS "#{schema}" CASCADE)) }
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
