require "json"

module RailsSync
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
        capture(env, status, headers, response) if enabled?
        [status, headers, response]
      end

      private

      def enabled?
        @enabled
      end

      def capture(env, status, headers, response)
        content_type = headers["Content-Type"] || headers["content-type"]
        return unless content_type&.include?("application/json")

        template = @route_resolver.call(env)
        return if template.nil?

        body = +""
        response.each { |part| body << part }

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
            "body" => safe_parse(body)
          }
        )
      rescue StandardError
        nil # never break a request because of capture
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
