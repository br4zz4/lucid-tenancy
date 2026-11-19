require "rails/generators"

module Lucid
  module Tenancy
    module Generators
      # Creates config/initializers/lucid_tenancy.rb with every option and its default.
      #
      #   bin/rails g lucid:tenancy:install
      class InstallGenerator < ::Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)
        namespace "lucid:tenancy:install"
        desc "Creates config/initializers/lucid_tenancy.rb"

        def create_initializer
          template "lucid_tenancy.rb.tt", "config/initializers/lucid_tenancy.rb"
        end
      end
    end
  end
end
