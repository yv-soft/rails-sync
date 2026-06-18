require "action_dispatch"

RSpec.describe RailsSync::Static::RouteExtractor do
  def route_set
    set = ActionDispatch::Routing::RouteSet.new
    set.draw do
      get "/users/:id", to: "users#show"
      post "/users", to: "users#create"
    end
    set
  end

  it "extracts verb, OpenAPI path, controller, action, path params" do
    result = described_class.new(route_set).extract
    expect(result).to include(
      a_hash_including(verb: "GET", path: "/users/{id}", controller: "users", action: "show", path_params: ["id"]),
      a_hash_including(verb: "POST", path: "/users", controller: "users", action: "create", path_params: [])
    )
  end
end
