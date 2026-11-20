# frozen_string_literal: true

require "rubocop"

require_relative "../../rubocop/cop/lucid/tenancy/blank_line_after_declaration"

# Loaded on demand with +require: lucid/tenancy/rubocop+ in +.rubocop.yml+; the gem does not depend on rubocop.
module Lucid
  module Tenancy
    module RuboCopConfig
      DEFAULT_PATH = File.expand_path("../../../config/default.yml", __dir__)

      module_function

      # Merges the cop defaults into RuboCop's default configuration.
      def inject!
        hash = RuboCop::ConfigLoader.send(:load_yaml_configuration, DEFAULT_PATH)
        config = RuboCop::Config.new(hash, DEFAULT_PATH).tap(&:make_excludes_absolute)
        config = RuboCop::ConfigLoader.merge_with_default(config, DEFAULT_PATH, unset_nil: false)
        RuboCop::ConfigLoader.instance_variable_set(:@default_configuration, config)
      end
    end
  end
end

Lucid::Tenancy::RuboCopConfig.inject!
