# Migrations

Every migration declares where it runs.

```ruby
class AddCpfToStudents < ActiveRecord::Migration[8.1]
  tenancy :tenant

  def change
    add_column :students, :cpf, :string
  end
end

class CreatePlans < ActiveRecord::Migration[8.1]
  tenancy :shared

  def change
    create_table(:plans) { |t| t.string :name }
  end
end
```

`tenancy :tenant` runs the migration in the template schema and in every tenant schema. `tenancy :shared` runs it once, in the shared schema. A migration without the declaration fails with `Lucid::Tenancy::Error::MissingTenancyDeclaration`, naming the file. The gem reads the declaration from the class, never from the text of the file.

Write the body as if there were one schema. The gem puts the right schema on the path before the migration runs.

## Running

```sh
bin/rails db:migrate
bin/rails db:rollback          # STEP=n for more
bin/rails lucid:tenancy:status
```

`db:migrate` and `db:rollback` are replaced by `lucid:tenancy:migrate` and `lucid:tenancy:rollback`. Each schema keeps its own `schema_migrations`, so a new tenant, a lagging tenant and the shared schema can each be at a different version. Migrating brings every schema up to date by running the pending migrations in it. The gem never drops or recreates a schema.

`lucid:tenancy:status` prints the pending versions for each schema, or `up to date`.

Rollback undoes the last `STEP` migrations of each kind in every schema.

## The dump

After migrating or rolling back, the gem writes `db/tenant_schema.rb` from the template schema. That file is what `provision` loads for new tenants ([Provisioning](provisioning.md)). Regenerate it by hand with:

```sh
bin/rails lucid:tenancy:dump
```

Commit the file with the migration. `db/schema.rb` keeps describing the shared schema as usual.

## CI

```sh
bin/rails lucid:tenancy:check
```

The task aborts with `db/tenant_schema.rb is out of date, run lucid:tenancy:dump` when the committed dump differs from the template schema. Run it after migrating in CI to catch a migration committed without its dump.
