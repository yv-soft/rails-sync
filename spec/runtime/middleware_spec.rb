require "tmpdir"
require "rack/mock"
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

  it "buffers the body so a single-enumeration response is not double-consumed" do
    store = RailsSync::Runtime::ObservationStore.new(File.join(@dir, "once.jsonl"))
    json = { "id" => 1 }.to_json
    once_body = Class.new do
      def initialize(parts)
        @parts = parts
        @read = false
      end

      def each
        raise "body enumerated more than once" if @read
        @read = true
        @parts.each { |p| yield p }
      end
    end.new([json])

    inner = ->(_env) { [200, { "Content-Type" => "application/json" }, once_body] }
    mw = RailsSync::Runtime::Middleware.new(inner, store: store, route_resolver: ->(_e) { "/things" }, enabled: true)

    status, _headers, returned_body = mw.call(Rack::MockRequest.env_for("/things"))
    collected = +""
    returned_body.each { |p| collected << p }

    expect(status).to eq(200)
    expect(collected).to eq(json)
    expect(store.all.size).to eq(1)
  end

  it "does not record non-JSON responses" do
    store = RailsSync::Runtime::ObservationStore.new(File.join(@dir, "html.jsonl"))
    inner = ->(_env) { [200, { "Content-Type" => "text/html" }, ["<h1>hi</h1>"]] }
    mw = RailsSync::Runtime::Middleware.new(inner, store: store, route_resolver: ->(_e) { "/x" }, enabled: true)
    mw.call(Rack::MockRequest.env_for("/x"))
    expect(store.all).to eq([])
  end

  it "does not record when the route resolver returns nil" do
    store = RailsSync::Runtime::ObservationStore.new(File.join(@dir, "noroute.jsonl"))
    inner = ->(_env) { [200, { "Content-Type" => "application/json" }, ["{}"]] }
    mw = RailsSync::Runtime::Middleware.new(inner, store: store, route_resolver: ->(_e) { nil }, enabled: true)
    mw.call(Rack::MockRequest.env_for("/x"))
    expect(store.all).to eq([])
  end
end
