require "tmpdir"

RSpec.describe "end-to-end build", type: :integration do
  before(:all) do
    ENV["RAILS_CONTRACT_SYNC"] = "1"
    require File.expand_path("dummy/config/application", __dir__)
    Dummy::Application.initialize! unless Dummy::Application.initialized?
  end

  it "captures traffic and writes a merged contract" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "openapi.yml")
      store = RailsContractSync::Runtime::ObservationStore.new(File.join(dir, "obs.jsonl"))
      resolver = RailsContractSync::Runtime::RouteResolver.new(Dummy::Application.routes)

      inner = Dummy::Application
      mw = RailsContractSync::Runtime::Middleware.new(inner, store: store, route_resolver: resolver, enabled: true)

      env_post = Rack::MockRequest.env_for("/users", method: "POST",
        input: { user: { name: "Grace" } }.to_json, "CONTENT_TYPE" => "application/json")
      mw.call(env_post)
      env_get = Rack::MockRequest.env_for("/users/7", method: "GET")
      mw.call(env_get)

      sources = { "users" => File.read(File.expand_path("dummy/app/controllers/users_controller.rb", __dir__)) }
      RailsContractSync.build(route_set: Dummy::Application.routes, controller_sources: sources, observation_store: store, output_path: out)

      doc = RailsContractSync::OpenAPIDocument.load_file(out)
      expect(doc.operation("/users", "post")["responses"]).to have_key("201")
      expect(doc.operation("/users/{id}", "get")["responses"]).to have_key("200")

      # Idempotency + prose preservation
      first = File.read(out)
      reloaded = doc.to_h
      reloaded["paths"]["/users"]["post"]["summary"] = "Create a user"
      RailsContractSync::OpenAPIDocument.new(reloaded).write(out)
      RailsContractSync.build(route_set: Dummy::Application.routes, controller_sources: sources, observation_store: store, output_path: out)
      expect(RailsContractSync::OpenAPIDocument.load_file(out).operation("/users", "post")["summary"]).to eq("Create a user")
    end
  end
end
