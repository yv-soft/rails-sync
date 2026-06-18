module RailsSync
  module Merger
    HUMAN_OP_KEYS = %w[summary description tags].freeze

    module_function

    def merge(existing, fresh, prune: false)
      result = fresh.to_h
      result_paths = result["paths"] ||= {}
      return OpenAPIDocument.new(result) if existing.nil?

      existing_h = existing.to_h
      result["info"] = existing_h["info"] if existing_h["info"]

      (existing_h["paths"] || {}).each do |path, ops|
        ops.each do |verb, existing_op|
          target = result_paths.dig(path, verb)
          if target
            HUMAN_OP_KEYS.each { |k| target[k] = existing_op[k] if existing_op.key?(k) }
            preserve_descriptions(existing_op["responses"], target["responses"])
          elsif !prune
            (result_paths[path] ||= {})[verb] = existing_op.merge("x-rails-sync-stale" => true)
          end
        end
      end

      OpenAPIDocument.new(result)
    end

    # Recursively copy "description" from old schema nodes onto matching new ones.
    def preserve_descriptions(old_node, new_node)
      return unless old_node.is_a?(Hash) && new_node.is_a?(Hash)

      new_node["description"] = old_node["description"] if old_node.key?("description")
      old_node.each do |key, old_child|
        next if key == "description"

        preserve_descriptions(old_child, new_node[key])
      end
    end
  end
end
