module RailsContractSync
  module Static
    class RouteExtractor
      VERBS = %w[GET POST PUT PATCH DELETE].freeze

      def initialize(route_set)
        @route_set = route_set
      end

      def extract
        @route_set.routes.filter_map do |route|
          controller = route.defaults[:controller]
          action = route.defaults[:action]
          next if controller.nil? || action.nil?

          verb = VERBS.find { |m| route.verb.to_s.include?(m) }
          next if verb.nil?

          spec = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
          { verb: verb,
            path: spec.gsub(/:([a-z_]+)/) { "{#{Regexp.last_match(1)}}" },
            controller: controller,
            action: action,
            path_params: spec.scan(/:([a-z_]+)/).flatten - ["format"] }
        end
      end
    end
  end
end
