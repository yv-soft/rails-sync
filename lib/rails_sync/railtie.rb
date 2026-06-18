module RailsSync
  class Railtie < Rails::Railtie
    initializer "rails_sync.middleware" do |app|
      if RailsSync.configuration.enabled?
        resolver = Runtime::RouteResolver.new(app.routes)
        app.middleware.use(
          Runtime::Middleware,
          store: RailsSync.configuration.observation_store,
          route_resolver: resolver,
          enabled: true
        )
      end
    end

    rake_tasks do
      load File.expand_path("../tasks/rails_sync.rake", __dir__)
    end
  end
end
