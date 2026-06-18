require "json"

module RailsContractSync
  module Runtime
    class Middleware
      def initialize(app, store:, route_resolver:, enabled: true)
        @app = app
        @store = store
        @route_resolver = route_resolver
        @enabled = enabled
      end

      def call(env)
        status, headers, response = @app.call(env)
        return [status, headers, response] unless enabled?

        content_type = headers["Content-Type"] || headers["content-type"]
        return [status, headers, response] unless content_type&.include?("application/json")

        # Buffer the body so both the recorder and the downstream server can read it.
        parts = []
        response.each { |part| parts << part }
        response.close if response.respond_to?(:close)

        record(env, status, headers, content_type, parts)
        [status, headers, parts]
      end

      private

      def enabled?
        @enabled
      end

      def record(env, status, headers, content_type, parts)
        template = @route_resolver.call(env)
        return if template.nil?

        @store.append(
          "verb" => env["REQUEST_METHOD"],
          "path_template" => template,
          "request" => {
            "content_type" => env["CONTENT_TYPE"],
            "params" => request_params(env)
          },
          "response" => {
            "status" => status,
            "content_type" => content_type,
            "body" => safe_parse(parts.join)
          }
        )
      rescue StandardError
        nil
      end

      def request_params(env)
        input = env["rack.input"]
        return {} unless input

        raw = input.read
        input.rewind if input.respond_to?(:rewind)
        return {} if raw.nil? || raw.empty?

        parsed = safe_parse(raw)
        parsed.is_a?(Hash) ? parsed : {}
      end

      def safe_parse(raw)
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
