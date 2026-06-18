module RailsSync
  module SchemaInferrer
    module_function

    def infer(value)
      case value
      when nil then { "type" => "null" }
      when true, false then { "type" => "boolean" }
      when Integer then { "type" => "integer" }
      when Float then { "type" => "number" }
      when String then { "type" => "string" }
      when Array then infer_array(value)
      when Hash then infer_object(value)
      else { "type" => "string" }
      end
    end

    def infer_array(array)
      { "type" => "array", "items" => infer_all(array) }
    end

    def infer_object(hash)
      props = {}
      hash.each { |k, v| props[k.to_s] = infer(v) }
      { "type" => "object", "properties" => props, "required" => hash.keys.map(&:to_s).sort }
    end

    def infer_all(values)
      values.map { |v| infer(v) }.reduce(nil) { |acc, s| acc ? merge(acc, s) : s } || {}
    end

    def merge(a, b)
      a ||= {}
      b ||= {}
      return b if a.empty?
      return a if b.empty?

      types = (Array(a["type"]) | Array(b["type"])).sort
      # Widen integer + number to just number
      if types == ["integer", "number"]
        types = ["number"]
      end
      result = { "type" => types.length == 1 ? types.first : types }
      result.merge!(merge_object(a, b)) if types.include?("object")
      result["items"] = merge(a["items"] || {}, b["items"] || {}) if types.include?("array")
      result
    end

    def merge_object(a, b)
      props_a = a["properties"] || {}
      props_b = b["properties"] || {}
      merged = {}
      (props_a.keys | props_b.keys).each do |k|
        merged[k] = if props_a[k] && props_b[k]
          merge(props_a[k], props_b[k])
        else
          props_a[k] || props_b[k]
        end
      end
      required = ((a["required"] || []) & (b["required"] || [])).sort
      { "properties" => merged, "required" => required }
    end
  end
end
