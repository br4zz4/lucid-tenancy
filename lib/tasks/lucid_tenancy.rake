namespace :lucid do
  namespace :tenancy do
    desc "Migrates the shared schema, the template and every tenant"
    task migrate: "db:load_config" do
      Lucid::Tenancy::Migrator.migrate
      Rake::Task["lucid:tenancy:dump"].invoke
    end

    desc "Rolls back STEP migrations (default 1) in every schema"
    task rollback: "db:load_config" do
      Lucid::Tenancy::Migrator.rollback(steps: ENV.fetch("STEP", 1).to_i)
      Rake::Task["lucid:tenancy:dump"].invoke
    end

    desc "Lists pending migrations per schema"
    task status: "db:load_config" do
      Lucid::Tenancy::Migrator.pending.each { |schema, versions| puts "#{schema}: #{versions.empty? ? 'up to date' : versions.join(', ')}" }
    end

    desc "Writes db/tenant_schema.rb from the template schema"
    task dump: "db:load_config" do
      Lucid::Tenancy::SchemaDump.write if Lucid::Tenancy::Template.exists?
    end

    desc "Fails when db/tenant_schema.rb is out of sync with the template schema"
    task check: "db:load_config" do
      abort "db/tenant_schema.rb is out of date, run lucid:tenancy:dump" unless Lucid::Tenancy::SchemaDump.in_sync?
    end
  end
end

if Rake::Task.task_defined?("db:migrate")
  Rake::Task["db:migrate"].clear
  Rake::Task["db:rollback"].clear if Rake::Task.task_defined?("db:rollback")
end

namespace :db do
  desc "Migrates the shared schema, the template and every tenant"
  task migrate: "db:load_config" do
    Rake::Task["lucid:tenancy:migrate"].invoke
  end

  desc "Rolls back the last migration (STEP=n) in every schema"
  task rollback: "db:load_config" do
    Rake::Task["lucid:tenancy:rollback"].invoke
  end
end
