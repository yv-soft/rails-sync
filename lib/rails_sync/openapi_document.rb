require "yaml"

module RailsSync
  class OpenAPIDocument
    def self.load_file(path)
      return new unless File.exist?(path)

      new(YAML.safe_load_file(path) || nil)
    end

    def initialize(hash = nil)
      @doc = hash || skeleton
      @doc["paths"] ||= {}
    end

    def paths
      @doc["paths"]
    end

    def operation(path, verb)
      paths.dig(path, verb.to_s.downcase)
    end

    def set_operation(path, verb, op_hash)
      (paths[path] ||= {})[verb.to_s.downcase] = op_hash
    end

    def to_h
      deep_sort(deep_dup(@doc))
    end

    def to_yaml
      to_h.to_yaml
    end

    def write(path)
      File.write(path, to_yaml)
    end

    private

    def skeleton
      { "openapi" => "3.1.0", "info" => { "title" => "API", "version" => "1.0.0" }, "paths" => {} }
    end

    def deep_dup(obj)
      case obj
      when Hash then obj.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
      when Array then obj.map { |v| deep_dup(v) }
      else obj
      end
    end

    def deep_sort(obj)
      case obj
      when Hash then obj.keys.sort.each_with_object({}) { |k, h| h[k] = deep_sort(obj[k]) }
      when Array then obj.map { |v| deep_sort(v) }
      else obj
      end
    end
  end
end
