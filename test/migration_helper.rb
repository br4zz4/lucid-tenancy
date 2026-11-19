require "test_helper"

class MigrationTenancyTest < TenancyTest
  TEMPLATE = "tt_template".freeze

  def setup
    super
    @counter = 0
    connection.execute("DROP TABLE IF EXISTS public.schema_migrations")
    connection.execute("DROP TABLE IF EXISTS public.ar_internal_metadata")
    use_dump(VALID_DUMP)
    @klass = define_tenant_model
    Lucid::Tenancy.configure do |config|
      config.tenant_model = "TtOrganization"
      config.template_schema = TEMPLATE
    end
    @migrations_dir = Dir.mktmpdir("tenancy_migrations")
    @test_dirs << @migrations_dir
  end

  def teardown
    super
    connection.execute(%(DROP SCHEMA IF EXISTS "#{TEMPLATE}" CASCADE))
    connection.execute("DROP TABLE IF EXISTS public.things")
    connection.execute("DROP TABLE IF EXISTS public.settings_things")
    connection.execute("DROP TABLE IF EXISTS public.schema_migrations")
    connection.execute("DROP TABLE IF EXISTS public.ar_internal_metadata")
  end

  def prepare_template
    @test_schemas << TEMPLATE
    Lucid::Tenancy::Template.create!
    Lucid::Tenancy::Schema.with_path(TEMPLATE) { Lucid::Tenancy::Provisioner.load_dump(Lucid::Tenancy.configuration.tenant_schema_path) }
  end

  def provision_all(*subdomains)
    subdomains.map { |subdomain| provision_tenant(@klass, subdomain) }
  end

  def write_migration(version, name, mode:, body:)
    class_name = name.camelize
    @test_constants << class_name
    declaration = mode ? "tenancy :#{mode}\n" : ""
    File.write(File.join(@migrations_dir, "#{version}_#{name}.rb"), <<~RUBY)
      class #{class_name} < ActiveRecord::Migration[7.2]
        #{declaration}
        def change
          #{body}
        end
      end
    RUBY
    class_name
  end

  def versions(schema)
    connection.select_values(%(SELECT version FROM "#{schema}".schema_migrations ORDER BY version))
  end

  def columns(schema, table)
    connection.select_values(
      "SELECT column_name FROM information_schema.columns WHERE table_schema = #{connection.quote(schema)} " \
      "AND table_name = #{connection.quote(table)} ORDER BY column_name"
    )
  end

  def tables(schema)
    connection.select_values(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = #{connection.quote(schema)} ORDER BY table_name"
    )
  end

  def migrator
    Lucid::Tenancy::Migrator
  end

  def migrate
    silence { migrator.migrate(paths: [@migrations_dir]) }
  end

  def rollback(steps: 1)
    silence { migrator.rollback(steps: steps, paths: [@migrations_dir]) }
  end

  def silence
    previous = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    yield
  ensure
    ActiveRecord::Migration.verbose = previous
  end
end
