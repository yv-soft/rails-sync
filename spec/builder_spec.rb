require "action_dispatch"
require "tmpdir"

RSpec.describe RailsContractSync::Builder do
  def route_set
    set = ActionDispatch::Routing::RouteSet.new
    set.draw { post "/users", to: "users#create" }
    set
  end

  let(:controller_sources) do
    { "users" => <<~RUBY }
      class UsersController < ApplicationController
        def create
          User.create(params.require(:user).permit(:name))
        end
      end
    RUBY
  end

  let(:observations) do
    [{
      "verb" => "POST", "path_template" => "/users",
      "request" => { "content_type" => "application/json", "params" => { "user" => { "name" => "Ada" } } },
      "response" => { "status" => 201, "content_type" => "application/json", "body" => { "id" => 7, "name" => "Ada" } }
    }]
  end

  it "assembles paths, request body, and responses from static + observations" do
    doc = described_class.new(
      route_set: route_set, controller_sources: controller_sources, observations: observations
    ).build_fresh.to_h
    op = doc["paths"]["/users"]["post"]
    expect(op["responses"]["201"]["content"]["application/json"]["schema"]).to eq(
      "type" => "object",
      "properties" => { "id" => { "type" => "integer" }, "name" => { "type" => "string" } },
      "required" => %w[id name]
    )
    body_schema = op["requestBody"]["content"]["application/json"]["schema"]
    expect(body_schema["properties"]["user"]["properties"]["name"]).to eq("type" => "string")
  end

  it "RailsContractSync.build writes and merges into the output file" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "openapi.yml")
      store = RailsContractSync::Runtime::ObservationStore.new(File.join(dir, "obs.jsonl"))
      observations.each { |o| store.append(o) }
      RailsContractSync.build(route_set: route_set, controller_sources: controller_sources, observation_store: store, output_path: out)
      reloaded = RailsContractSync::OpenAPIDocument.load_file(out)
      expect(reloaded.operation("/users", "post")).not_to be_nil
    end
  end
end
