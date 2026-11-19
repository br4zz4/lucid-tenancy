require "rails/railtie"

module Lucid
  module Tenancy
    class Railtie < ::Rails::Railtie
      rake_tasks do
        load File.expand_path("../../tasks/lucid_tenancy.rake", __dir__)
      end
    end
  end
end
