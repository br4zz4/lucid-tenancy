module Lucid
  module Tenancy
    # RSpec helpers: +require "lucid/tenancy/rspec"+ and tag an example (or group) with +tenant: "alfa"+.
    #
    # @example
    #   RSpec.describe Student, tenant: "alfa" do
    #   end
    module RSpec
      def self.configure!
        ::RSpec.configure do |config|
          config.around(:each) do |example|
            identifier = example.metadata[:tenant]
            if identifier
              Lucid::Tenancy.with(tenant: identifier) { example.run }
            else
              example.run
            end
          end
        end
      end
    end
  end
end

Lucid::Tenancy::RSpec.configure! if defined?(::RSpec)
