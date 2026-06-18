module RailsContractSync
  class Railtie < Rails::Railtie
    initializer "rails_contract_sync.middleware" do |app|
      if RailsContractSync.configuration.enabled?
        resolver = Runtime::RouteResolver.new(app.routes)
        app.middleware.use(
          Runtime::Middleware,
          store: RailsContractSync.configuration.observation_store,
          route_resolver: resolver,
          enabled: true
        )
      end
    end

    rake_tasks do
      load File.expand_path("../tasks/rails_contract_sync.rake", __dir__)
    end
  end
end
