module RailsContractSync
  module Runtime
    class RouteResolver
      def initialize(route_set)
        @routes = Static::RouteExtractor.new(route_set).extract
      end

      def call(env)
        params = env["action_dispatch.request.path_parameters"]
        return nil unless params

        controller = params[:controller]
        action = params[:action]
        match = @routes.find do |r|
          r[:controller] == controller && r[:action] == action && r[:verb] == env["REQUEST_METHOD"]
        end
        match&.fetch(:path)
      end
    end
  end
end
