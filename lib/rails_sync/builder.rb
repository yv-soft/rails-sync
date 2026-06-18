module RailsSync
  class Builder
    def initialize(route_set:, controller_sources: {}, observations: [])
      @route_set = route_set
      @controller_sources = controller_sources
      @observations = observations
    end

    def build_fresh
      doc = OpenAPIDocument.new
      routes = Static::RouteExtractor.new(@route_set).extract
      params_by_controller = extract_params

      routes.each do |route|
        op = { "responses" => {} }
        add_request_body(op, route, params_by_controller)
        add_observed(op, route)
        op["responses"]["default"] = { "description" => "" } if op["responses"].empty?
        doc.set_operation(route[:path], route[:verb], op)
      end
      doc
    end

    private

    def extract_params
      @controller_sources.transform_values { |src| Static::ParamsExtractor.extract(src) }
    end

    def add_request_body(op, route, params_by_controller)
      tree = params_by_controller.dig(route[:controller], route[:action])
      static_schema = tree ? tree_to_schema(tree) : nil
      runtime_schema = observed_request_schema(route)
      schema = [static_schema, runtime_schema].compact.reduce(nil) { |a, s| a ? SchemaInferrer.merge(a, s) : s }
      return if schema.nil?

      op["requestBody"] = { "content" => { "application/json" => { "schema" => schema } } }
    end

    def observed_request_schema(route)
      bodies = matching(route).map { |o| o.dig("request", "params") }.compact
      bodies.empty? ? nil : SchemaInferrer.infer_all(bodies)
    end

    def add_observed(op, route)
      matching(route).group_by { |o| o.dig("response", "status") }.each do |status, group|
        bodies = group.map { |o| o.dig("response", "body") }
        op["responses"][status.to_s] = {
          "description" => "",
          "content" => { "application/json" => { "schema" => SchemaInferrer.infer_all(bodies) } }
        }
      end
    end

    def matching(route)
      @observations.select { |o| o["verb"] == route[:verb] && o["path_template"] == route[:path] }
    end

    def tree_to_schema(tree)
      case tree
      when nil then {}
      when Array then { "type" => "array", "items" => tree_to_schema(tree.first) }
      when Hash
        props = tree.transform_values { |v| tree_to_schema(v) }
        { "type" => "object", "properties" => props }
      end
    end
  end

  module_function

  def generate(route_set:, controller_sources:, output_path:, prune: false)
    write_merged(route_set: route_set, controller_sources: controller_sources, observations: [], output_path: output_path, prune: prune)
  end

  def build(route_set:, controller_sources:, observation_store:, output_path:, prune: false)
    write_merged(route_set: route_set, controller_sources: controller_sources, observations: observation_store.all, output_path: output_path, prune: prune)
  end

  def write_merged(route_set:, controller_sources:, observations:, output_path:, prune:)
    fresh = Builder.new(route_set: route_set, controller_sources: controller_sources, observations: observations).build_fresh
    existing = File.exist?(output_path) ? OpenAPIDocument.load_file(output_path) : nil
    merged = Merger.merge(existing, fresh, prune: prune)
    merged.write(output_path)
    merged
  end
end
