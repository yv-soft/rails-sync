require "prism"

module RailsSync
  module Static
    module ParamsExtractor
      module_function

      def extract(source)
        program = Prism.parse(source).value
        actions = {}
        each_def(program) do |def_node|
          tree = first_permit_tree(def_node.body)
          actions[def_node.name.to_s] = tree if tree
        end
        actions
      end

      def each_def(node, &block)
        return unless node

        yield node if node.is_a?(Prism::DefNode)
        node.compact_child_nodes.each { |child| each_def(child, &block) }
      end

      # Depth-first: return the tree for the first `permit` call found.
      def first_permit_tree(node)
        return nil unless node

        if node.is_a?(Prism::CallNode) && node.name == :permit
          tree = permit_args_to_tree(node.arguments)
          key = require_key(node.receiver)
          return key ? { key => tree } : tree
        end

        node.compact_child_nodes.each do |child|
          found = first_permit_tree(child)
          return found if found
        end
        nil
      end

      def require_key(receiver)
        return nil unless receiver.is_a?(Prism::CallNode) && receiver.name == :require

        arg = receiver.arguments&.arguments&.first
        arg.is_a?(Prism::SymbolNode) ? arg.unescaped : nil
      end

      def permit_args_to_tree(arguments_node)
        tree = {}
        (arguments_node&.arguments || []).each do |arg|
          case arg
          when Prism::SymbolNode
            tree[arg.unescaped] = nil
          when Prism::KeywordHashNode, Prism::HashNode
            arg.elements.each do |assoc|
              next unless assoc.is_a?(Prism::AssocNode) && assoc.key.is_a?(Prism::SymbolNode)

              tree[assoc.key.unescaped] = value_to_tree(assoc.value)
            end
          end
        end
        tree
      end

      def value_to_tree(value)
        return nil unless value.is_a?(Prism::ArrayNode)
        return [nil] if value.elements.empty?

        nested = {}
        value.elements.each do |el|
          nested[el.unescaped] = nil if el.is_a?(Prism::SymbolNode)
        end
        nested.empty? ? nil : nested
      end
    end
  end
end
