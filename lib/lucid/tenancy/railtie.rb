require "rails/railtie"

module Lucid
  module Tenancy
    class Railtie < ::Rails::Railtie
      initializer "lucid_tenancy.middleware" do |app|
        app.middleware.insert_before ActionDispatch::Cookies, Lucid::Tenancy::Middleware
      end

      initializer "lucid_tenancy.active_job" do
        ActiveSupport.on_load(:active_job) { include Lucid::Tenancy::ActiveJobExtension }
      end

      rake_tasks do
        load File.expand_path("../../tasks/lucid_tenancy.rake", __dir__)
      end
    end
  end
end
