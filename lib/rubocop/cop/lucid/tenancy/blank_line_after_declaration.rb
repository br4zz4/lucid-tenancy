# frozen_string_literal: true

module RuboCop
  module Cop
    module Lucid
      module Tenancy
        # Requires a blank line after the +tenancy :tenant+ / +tenancy :shared+ declaration of a migration.
        #
        # @example
        #   # bad
        #   tenancy :tenant
        #   def change; end
        #
        #   # good
        #   tenancy :tenant
        #
        #   def change; end
        class BlankLineAfterDeclaration < RuboCop::Cop::Base
          extend RuboCop::Cop::AutoCorrector

          MSG = "Add a blank line after the tenancy declaration."

          def on_send(node)
            return unless node.receiver.nil? && node.method?(:tenancy)
            return if blank_or_end_after?(node)

            add_offense(node) { |corrector| corrector.insert_after(node, "\n") }
          end

          private

          def blank_or_end_after?(node)
            following = processed_source.lines[node.last_line]
            following.nil? || following.strip.empty?
          end
        end
      end
    end
  end
end
