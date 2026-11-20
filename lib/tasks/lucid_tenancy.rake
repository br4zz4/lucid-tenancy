namespace :lucid do
  namespace :tenancy do
    desc "Migrates the shared schema, the template and every tenant"
    task migrate: "db:load_config" do
      Lucid::Tenancy::Migrator.migrate
      Rake::Task["lucid:tenancy:dump"].invoke
      dump_task = %w[db:schema:dump:primary db:schema:dump].find { |name| Rake::Task.task_defined?(name) }
      Rake::Task[dump_task].invoke if dump_task
    end

    desc "Rolls back STEP migrations (default 1) in every schema"
    task rollback: "db:load_config" do
      Lucid::Tenancy::Migrator.rollback(steps: ENV.fetch("STEP", 1).to_i)
      Rake::Task["lucid:tenancy:dump"].invoke
      dump_task = %w[db:schema:dump:primary db:schema:dump].find { |name| Rake::Task.task_defined?(name) }
      Rake::Task[dump_task].invoke if dump_task
    end

    desc "Lists pending migrations per schema"
    task status: "db:load_config" do
      Lucid::Tenancy::Migrator.pending.each { |schema, versions| puts "#{schema}: #{versions.empty? ? 'up to date' : versions.join(', ')}" }
    end

    desc "Creates the version table of a tenant schema that has none, marked in sync with the template"
    task :baseline, [:identifier] => "db:load_config" do |_task, args|
      tenants = args[:identifier] ? [Lucid::Tenancy.send(:resolve, args[:identifier])] : Lucid::Tenancy.to_a
      tenants.each { |tenant| puts "baseline: #{Lucid::Tenancy.baseline(tenant)}" }
    end

    desc "Writes the tenant schema dump (config.tenant_schema_path) from the template schema"
    task dump: "db:load_config" do
      Lucid::Tenancy::SchemaDump.write if Lucid::Tenancy::Template.exists?
    end

    desc "Fails when the tenant schema dump (config.tenant_schema_path) is out of sync with the template schema"
    task check: "db:load_config" do
      abort "#{Lucid::Tenancy.configuration.tenant_schema_path} is out of date, run lucid:tenancy:dump" unless Lucid::Tenancy::SchemaDump.in_sync?
    end
  end
end

%w[db:migrate db:rollback db:migrate:status db:migrate:up db:migrate:down db:migrate:redo].each do |name|
  Rake::Task[name].clear if Rake::Task.task_defined?(name)
end

namespace :db do
  namespace :migrate do
    desc "Lists pending migrations per schema"
    task status: "db:load_config" do
      Rake::Task["lucid:tenancy:status"].invoke
    end

    %w[up down redo].each do |name|
      desc "Not supported by lucid-tenancy: use db:migrate and db:rollback"
      task name => "db:load_config" do
        abort "db:migrate:#{name} runs in the shared schema only; use db:migrate or db:rollback STEP=n with lucid-tenancy"
      end
    end
  end
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

  task :prepare do
    Lucid::Tenancy::Migrator.migrate
    Rake::Task["lucid:tenancy:dump"].invoke
  end
end
