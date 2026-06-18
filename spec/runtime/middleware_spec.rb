require "tmpdir"
require "rack/test"
require "json"

RSpec.describe RailsSync::Runtime::Middleware do
  include Rack::Test::Methods

  attr_reader :store

  def app
    @store = RailsSync::Runtime::ObservationStore.new(File.join(@dir, "obs.jsonl"))
    inner = lambda do |_env|
      [201, { "Content-Type" => "application/json" }, [{ "id" => 7, "name" => "Ada" }.to_json]]
    end
    RailsSync::Runtime::Middleware.new(
      inner,
      store: @store,
      route_resolver: ->(_env) { "/users" },
      enabled: true
    )
  end

  around { |ex| Dir.mktmpdir { |d| @dir = d; ex.run } }

  it "records the response body and request for JSON responses" do
    post "/users", { "user" => { "name" => "Ada" } }.to_json, "CONTENT_TYPE" => "application/json"
    obs = store.all
    expect(obs.size).to eq(1)
    expect(obs.first).to include(
      "verb" => "POST",
      "path_template" => "/users",
      "response" => a_hash_including("status" => 201, "body" => { "id" => 7, "name" => "Ada" })
    )
    expect(obs.first["request"]["params"]).to eq("user" => { "name" => "Ada" })
  end

  it "does not record when disabled" do
    Dir.mktmpdir do |dir|
      disabled_store = RailsSync::Runtime::ObservationStore.new(File.join(dir, "obs.jsonl"))
      inner = lambda do |_env|
        [200, { "Content-Type" => "application/json" }, ['{"ok":true}']]
      end
      middleware = RailsSync::Runtime::Middleware.new(
        inner,
        store: disabled_store,
        route_resolver: ->(_e) { "/x" },
        enabled: false
      )
      middleware.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/x", "rack.input" => StringIO.new(""))
      expect(disabled_store.all).to eq([])
    end
  end
end
