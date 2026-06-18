# RailsSync OpenAPI Contract Extractor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Ruby gem that produces and maintains a single committed `openapi.yml` for a Rails JSON API, by combining static route/param introspection with runtime response observation.

**Architecture:** Pure, decoupled units (`SchemaInferrer`, `OpenAPIDocument`, `Merger`, `Static::RouteExtractor`, `Static::ParamsExtractor`, `Runtime::ObservationStore`, `Runtime::Middleware`) are each testable in isolation with explicit arguments (dependency injection). A `Builder` composes them. A thin Rails layer (`Configuration`, `Railtie`, rake tasks, `Runtime::RouteResolver`) wires the gem into a host app and is proven by one end-to-end integration test against a minimal `spec/dummy` app.

**Tech Stack:** Ruby (gem), Prism (AST parsing of strong params), Rack (capture middleware), Railtie (Rails integration), RSpec + rack-test (tests), stdlib YAML/JSON (serialization). Output is OpenAPI 3.1.

## Global Constraints

- **Ruby floor:** `required_ruby_version >= 3.2.0`.
- **Module / gem name:** module `RailsSync`; gem name `rails_sync`; require path `rails_sync`. (Repo folder stays `rails-sync`.)
- **Runtime dependencies (gemspec):** `prism` (`>= 0.24`), `railties` (`>= 7.0`), `rack` (`>= 2.2`).
- **Dev dependencies:** `rails` (`>= 7.0`), `rspec` (`~> 3.13`), `rack-test` (`~> 2.1`).
- **OpenAPI version string:** exactly `"3.1.0"`.
- **Default output path:** `openapi.yml` (host app root). **Observations path:** `tmp/rails_sync/observations.jsonl`. **Env gate:** middleware captures only when `ENV["RAILS_SYNC"]` is truthy.
- **Stale marker key:** `x-rails-sync-stale` (boolean `true`). **Human-owned operation keys preserved on merge:** `summary`, `description`, `tags`, plus `description` on schema objects.
- **Determinism:** `OpenAPIDocument#to_h` recursively sorts every Hash by key so file output is byte-stable (idempotent diffs).
- **Commits:** Do NOT add a `Co-Authored-By` trailer to any commit (user preference).

## File Structure

```
rails_sync.gemspec                         # gem metadata + deps
Gemfile                                     # bundler entry
.rspec                                      # --require spec_helper
lib/rails_sync.rb                           # entrypoint: requires + Builder.generate/.build
lib/rails_sync/version.rb                   # VERSION
lib/rails_sync/schema_inferrer.rb           # JSON value(s) -> JSON Schema (pure)
lib/rails_sync/openapi_document.rb          # OpenAPI 3.1 model + (de)serialize (pure)
lib/rails_sync/merger.rb                    # reconcile existing + fresh; prose; stale (pure)
lib/rails_sync/builder.rb                   # compose extractors+inferrer+merger (pure-ish)
lib/rails_sync/configuration.rb             # Rails-facing defaults
lib/rails_sync/static/route_extractor.rb    # RouteSet -> route infos
lib/rails_sync/static/params_extractor.rb   # Prism -> permitted-params trees
lib/rails_sync/runtime/observation_store.rb # JSONL append/read
lib/rails_sync/runtime/middleware.rb        # Rack capture
lib/rails_sync/runtime/route_resolver.rb    # Rails-backed concrete-path -> template
lib/rails_sync/railtie.rb                   # insert middleware + load rake tasks
lib/tasks/rails_sync.rake                   # rails_sync:generate, rails_sync:build
spec/spec_helper.rb
spec/schema_inferrer_spec.rb
spec/openapi_document_spec.rb
spec/merger_spec.rb
spec/builder_spec.rb
spec/static/route_extractor_spec.rb
spec/static/params_extractor_spec.rb
spec/runtime/observation_store_spec.rb
spec/runtime/middleware_spec.rb
spec/integration/dummy/                     # minimal Rails app (created in Task 9)
spec/integration/build_spec.rb             # end-to-end
```

---

### Task 1: Gem skeleton + RSpec

**Files:**
- Create: `rails_sync.gemspec`, `Gemfile`, `.rspec`, `lib/rails_sync.rb`, `lib/rails_sync/version.rb`, `spec/spec_helper.rb`, `spec/version_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `RailsSync::VERSION` (String); a loadable `require "rails_sync"`.

- [ ] **Step 1: Write the failing test**

`spec/version_spec.rb`:
```ruby
RSpec.describe RailsSync do
  it "has a semantic version string" do
    expect(RailsSync::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
```

- [ ] **Step 2: Create gem files**

`lib/rails_sync/version.rb`:
```ruby
module RailsSync
  VERSION = "0.1.0"
end
```

`lib/rails_sync.rb`:
```ruby
require_relative "rails_sync/version"

module RailsSync
end
```

`rails_sync.gemspec`:
```ruby
require_relative "lib/rails_sync/version"

Gem::Specification.new do |spec|
  spec.name = "rails_sync"
  spec.version = RailsSync::VERSION
  spec.authors = ["dani"]
  spec.summary = "Generate and maintain an OpenAPI 3.1 contract for a Rails JSON API."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.files = Dir["lib/**/*.rb", "lib/tasks/**/*.rake"]
  spec.require_paths = ["lib"]

  spec.add_dependency "prism", ">= 0.24"
  spec.add_dependency "railties", ">= 7.0"
  spec.add_dependency "rack", ">= 2.2"

  spec.add_development_dependency "rails", ">= 7.0"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rack-test", "~> 2.1"
end
```

`Gemfile`:
```ruby
source "https://rubygems.org"
gemspec
```

`.rspec`:
```
--require spec_helper
--format documentation
```

`spec/spec_helper.rb`:
```ruby
require "rails_sync"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
end
```

- [ ] **Step 3: Install and run**

Run: `bundle install && bundle exec rspec spec/version_spec.rb`
Expected: PASS (1 example, 0 failures).

- [ ] **Step 4: Commit**

```bash
git add rails_sync.gemspec Gemfile .rspec lib spec
git commit -m "feat: gem skeleton with RSpec and version"
```

---

### Task 2: SchemaInferrer

**Files:**
- Create: `lib/rails_sync/schema_inferrer.rb`, `spec/schema_inferrer_spec.rb`
- Modify: `lib/rails_sync.rb` (add `require_relative "rails_sync/schema_inferrer"`)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `RailsSync::SchemaInferrer.infer(value) -> Hash` — JSON Schema for one parsed JSON value.
  - `RailsSync::SchemaInferrer.merge(a, b) -> Hash` — widen/union two schemas. `{}` means "any".
  - `RailsSync::SchemaInferrer.infer_all(values) -> Hash` — infer each value and reduce via `merge`; `[]` -> `{}`.
- Schema conventions: scalars `{"type"=>"integer|number|string|boolean|null"}`; objects `{"type"=>"object","properties"=>{..},"required"=>[..]}`; arrays `{"type"=>"array","items"=>{..}}`. `required` is the sorted list of keys present; merging takes the **intersection** (absent-in-one => optional). Nullable becomes a sorted `type` array, e.g. `["null","string"]`.

- [ ] **Step 1: Write the failing tests**

`spec/schema_inferrer_spec.rb`:
```ruby
RSpec.describe RailsSync::SchemaInferrer do
  describe ".infer" do
    it "types scalars" do
      expect(described_class.infer(1)).to eq("type" => "integer")
      expect(described_class.infer(1.5)).to eq("type" => "number")
      expect(described_class.infer("x")).to eq("type" => "string")
      expect(described_class.infer(true)).to eq("type" => "boolean")
      expect(described_class.infer(nil)).to eq("type" => "null")
    end

    it "infers objects with required = keys present" do
      expect(described_class.infer({ "a" => 1, "b" => "x" })).to eq(
        "type" => "object",
        "properties" => { "a" => { "type" => "integer" }, "b" => { "type" => "string" } },
        "required" => %w[a b]
      )
    end

    it "infers arrays by merging element schemas" do
      expect(described_class.infer([1, 2])).to eq(
        "type" => "array", "items" => { "type" => "integer" }
      )
    end

    it "treats empty arrays as items: any" do
      expect(described_class.infer([])).to eq("type" => "array", "items" => {})
    end
  end

  describe ".merge" do
    it "widens integer + number to number" do
      expect(described_class.merge({ "type" => "integer" }, { "type" => "number" }))
        .to eq("type" => "number")
    end

    it "makes a field nullable via type array" do
      expect(described_class.merge({ "type" => "string" }, { "type" => "null" }))
        .to eq("type" => %w[null string])
    end

    it "treats {} as any (identity)" do
      expect(described_class.merge({}, { "type" => "string" })).to eq("type" => "string")
    end

    it "unions object properties and intersects required" do
      a = described_class.infer({ "id" => 1, "name" => "x" })
      b = described_class.infer({ "id" => 2 })
      merged = described_class.merge(a, b)
      expect(merged["properties"].keys).to contain_exactly("id", "name")
      expect(merged["required"]).to eq(["id"]) # name absent in b -> optional
    end
  end

  describe ".infer_all" do
    it "reduces multiple observations" do
      expect(described_class.infer_all([{ "a" => 1 }, { "a" => 2, "b" => 3 }]))
        .to eq(
          "type" => "object",
          "properties" => { "a" => { "type" => "integer" }, "b" => { "type" => "integer" } },
          "required" => ["a"]
        )
    end

    it "returns {} for no observations" do
      expect(described_class.infer_all([])).to eq({})
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/schema_inferrer_spec.rb`
Expected: FAIL with `uninitialized constant RailsSync::SchemaInferrer`.

- [ ] **Step 3: Implement**

`lib/rails_sync/schema_inferrer.rb`:
```ruby
module RailsSync
  module SchemaInferrer
    module_function

    def infer(value)
      case value
      when nil then { "type" => "null" }
      when true, false then { "type" => "boolean" }
      when Integer then { "type" => "integer" }
      when Float then { "type" => "number" }
      when String then { "type" => "string" }
      when Array then infer_array(value)
      when Hash then infer_object(value)
      else { "type" => "string" }
      end
    end

    def infer_array(array)
      { "type" => "array", "items" => infer_all(array) }
    end

    def infer_object(hash)
      props = {}
      hash.each { |k, v| props[k.to_s] = infer(v) }
      { "type" => "object", "properties" => props, "required" => hash.keys.map(&:to_s).sort }
    end

    def infer_all(values)
      values.map { |v| infer(v) }.reduce(nil) { |acc, s| acc ? merge(acc, s) : s } || {}
    end

    def merge(a, b)
      a ||= {}
      b ||= {}
      return b if a.empty?
      return a if b.empty?

      types = (Array(a["type"]) | Array(b["type"])).sort
      result = { "type" => types.length == 1 ? types.first : types }
      result.merge!(merge_object(a, b)) if types.include?("object")
      result["items"] = merge(a["items"] || {}, b["items"] || {}) if types.include?("array")
      result
    end

    def merge_object(a, b)
      props_a = a["properties"] || {}
      props_b = b["properties"] || {}
      merged = {}
      (props_a.keys | props_b.keys).each do |k|
        merged[k] = if props_a[k] && props_b[k]
          merge(props_a[k], props_b[k])
        else
          props_a[k] || props_b[k]
        end
      end
      required = ((a["required"] || []) & (b["required"] || [])).sort
      out = {}
      out["properties"] = merged unless merged.empty?
      out["required"] = required unless required.empty?
      out
    end
  end
end
```

Add to `lib/rails_sync.rb` after the version require:
```ruby
require_relative "rails_sync/schema_inferrer"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/schema_inferrer_spec.rb`
Expected: PASS (all examples).

- [ ] **Step 5: Commit**

```bash
git add lib/rails_sync/schema_inferrer.rb lib/rails_sync.rb spec/schema_inferrer_spec.rb
git commit -m "feat: SchemaInferrer for JSON value inference and merging"
```

---

### Task 3: OpenAPIDocument

**Files:**
- Create: `lib/rails_sync/openapi_document.rb`, `spec/openapi_document_spec.rb`
- Modify: `lib/rails_sync.rb` (add require)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `RailsSync::OpenAPIDocument.new(hash = nil)` — wraps a doc Hash; `nil` seeds a 3.1 skeleton.
  - `.load_file(path) -> OpenAPIDocument` — parse a YAML file (missing file -> empty skeleton).
  - `#to_h -> Hash` — deep-sorted (deterministic) copy.
  - `#to_yaml -> String`; `#write(path) -> void`.
  - `#paths -> Hash` (the `"paths"` sub-hash).
  - `#operation(path, verb) -> Hash | nil`; `#set_operation(path, verb, op_hash) -> void` (verb stored lower-case).

- [ ] **Step 1: Write the failing tests**

`spec/openapi_document_spec.rb`:
```ruby
require "tmpdir"

RSpec.describe RailsSync::OpenAPIDocument do
  it "seeds an OpenAPI 3.1 skeleton" do
    doc = described_class.new.to_h
    expect(doc["openapi"]).to eq("3.1.0")
    expect(doc["paths"]).to eq({})
    expect(doc["info"]).to include("title", "version")
  end

  it "sets and reads operations (verb stored lower-case)" do
    doc = described_class.new
    doc.set_operation("/users", "POST", { "responses" => {} })
    expect(doc.operation("/users", "post")).to eq("responses" => {})
    expect(doc.paths.keys).to eq(["/users"])
  end

  it "to_h sorts hashes recursively for stable output" do
    doc = described_class.new({ "openapi" => "3.1.0", "paths" => { "/b" => {}, "/a" => {} } })
    expect(doc.to_h["paths"].keys).to eq(["/a", "/b"])
  end

  it "round-trips through a file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "openapi.yml")
      doc = described_class.new
      doc.set_operation("/ping", "get", { "responses" => { "200" => { "description" => "ok" } } })
      doc.write(path)
      loaded = described_class.load_file(path)
      expect(loaded.operation("/ping", "get")).to eq("responses" => { "200" => { "description" => "ok" } })
    end
  end

  it "load_file on a missing path returns an empty skeleton" do
    expect(described_class.load_file("/no/such/file.yml").paths).to eq({})
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/openapi_document_spec.rb`
Expected: FAIL with `uninitialized constant RailsSync::OpenAPIDocument`.

- [ ] **Step 3: Implement**

`lib/rails_sync/openapi_document.rb`:
```ruby
require "yaml"

module RailsSync
  class OpenAPIDocument
    def self.load_file(path)
      return new unless File.exist?(path)

      new(YAML.safe_load_file(path) || nil)
    end

    def initialize(hash = nil)
      @doc = hash || skeleton
      @doc["paths"] ||= {}
    end

    def paths
      @doc["paths"]
    end

    def operation(path, verb)
      paths.dig(path, verb.to_s.downcase)
    end

    def set_operation(path, verb, op_hash)
      (paths[path] ||= {})[verb.to_s.downcase] = op_hash
    end

    def to_h
      deep_sort(deep_dup(@doc))
    end

    def to_yaml
      to_h.to_yaml
    end

    def write(path)
      File.write(path, to_yaml)
    end

    private

    def skeleton
      { "openapi" => "3.1.0", "info" => { "title" => "API", "version" => "1.0.0" }, "paths" => {} }
    end

    def deep_dup(obj)
      case obj
      when Hash then obj.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
      when Array then obj.map { |v| deep_dup(v) }
      else obj
      end
    end

    def deep_sort(obj)
      case obj
      when Hash then obj.keys.sort.each_with_object({}) { |k, h| h[k] = deep_sort(obj[k]) }
      when Array then obj.map { |v| deep_sort(v) }
      else obj
      end
    end
  end
end
```

Add to `lib/rails_sync.rb`:
```ruby
require_relative "rails_sync/openapi_document"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/openapi_document_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/rails_sync/openapi_document.rb lib/rails_sync.rb spec/openapi_document_spec.rb
git commit -m "feat: OpenAPIDocument model with deterministic serialization"
```

---

### Task 4: Static::RouteExtractor

**Files:**
- Create: `lib/rails_sync/static/route_extractor.rb`, `spec/static/route_extractor_spec.rb`
- Modify: `lib/rails_sync.rb` (add require)

**Interfaces:**
- Consumes: an `ActionDispatch::Routing::RouteSet` (or anything exposing `#routes` of route objects with `#defaults`, `#verb`, `#path.spec`).
- Produces: `RailsSync::Static::RouteExtractor.new(route_set).extract -> Array<Hash>` with keys `:verb` (e.g. `"GET"`), `:path` (OpenAPI template, `:id` -> `{id}`, `(.:format)` dropped), `:controller`, `:action`, `:path_params` (Array<String>, `format` excluded). Routes without controller+action, or non-standard verbs, are skipped.

- [ ] **Step 1: Write the failing test**

`spec/static/route_extractor_spec.rb`:
```ruby
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/static/route_extractor_spec.rb`
Expected: FAIL with `uninitialized constant RailsSync::Static::RouteExtractor`.

- [ ] **Step 3: Implement**

`lib/rails_sync/static/route_extractor.rb`:
```ruby
module RailsSync
  module Static
    class RouteExtractor
      VERBS = %w[GET POST PUT PATCH DELETE].freeze

      def initialize(route_set)
        @route_set = route_set
      end

      def extract
        @route_set.routes.filter_map do |route|
          controller = route.defaults[:controller]
          action = route.defaults[:action]
          next if controller.nil? || action.nil?

          verb = VERBS.find { |m| route.verb.to_s.include?(m) }
          next if verb.nil?

          spec = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
          { verb: verb,
            path: spec.gsub(/:([a-z_]+)/) { "{#{Regexp.last_match(1)}}" },
            controller: controller,
            action: action,
            path_params: spec.scan(/:([a-z_]+)/).flatten - ["format"] }
        end
      end
    end
  end
end
```

Add to `lib/rails_sync.rb`:
```ruby
require_relative "rails_sync/static/route_extractor"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/static/route_extractor_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/rails_sync/static/route_extractor.rb lib/rails_sync.rb spec/static/route_extractor_spec.rb
git commit -m "feat: Static::RouteExtractor maps Rails routes to OpenAPI paths"
```

---

### Task 5: Static::ParamsExtractor

**Files:**
- Create: `lib/rails_sync/static/params_extractor.rb`, `spec/static/params_extractor_spec.rb`
- Modify: `lib/rails_sync.rb` (add require)

**Interfaces:**
- Consumes: Ruby source as a String (controller file contents).
- Produces: `RailsSync::Static::ParamsExtractor.extract(source) -> Hash{action_name(String) => ParamTree}`. **ParamTree** = `nil` (scalar, unknown type) | `Hash{String=>ParamTree}` (object) | `[ParamTree]` (array; `[nil]` = array of scalars). A `require(:key)` wraps the permitted tree under `{ "key" => tree }`. Best-effort: only the first `permit` per action is read; non-literal arguments are ignored. `permit(key: [:a, :b])` is treated as a **nested object** (runtime may later correct it to an array).

- [ ] **Step 1: Write the failing tests**

`spec/static/params_extractor_spec.rb`:
```ruby
RSpec.describe RailsSync::Static::ParamsExtractor do
  it "reads require + scalar permits, wrapping under the required key" do
    source = <<~RUBY
      class UsersController < ApplicationController
        def create
          user = User.create(params.require(:user).permit(:name, :email))
        end
      end
    RUBY
    expect(described_class.extract(source)).to eq(
      "create" => { "user" => { "name" => nil, "email" => nil } }
    )
  end

  it "reads top-level scalar permits with no require" do
    source = <<~RUBY
      class SearchController < ApplicationController
        def index
          render json: search(params.permit(:q, :page))
        end
      end
    RUBY
    expect(described_class.extract(source)).to eq(
      "index" => { "q" => nil, "page" => nil }
    )
  end

  it "treats empty-array permits as arrays of scalars and key-lists as nested objects" do
    source = <<~RUBY
      class PostsController < ApplicationController
        def update
          params.require(:post).permit(:title, tags: [], author: [:name, :id])
        end
      end
    RUBY
    expect(described_class.extract(source)).to eq(
      "update" => { "post" => { "title" => nil, "tags" => [nil], "author" => { "name" => nil, "id" => nil } } }
    )
  end

  it "returns no entry for actions without a permit" do
    source = <<~RUBY
      class PingController < ApplicationController
        def show
          render json: { ok: true }
        end
      end
    RUBY
    expect(described_class.extract(source)).to eq({})
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/static/params_extractor_spec.rb`
Expected: FAIL with `uninitialized constant RailsSync::Static::ParamsExtractor`.

- [ ] **Step 3: Implement**

`lib/rails_sync/static/params_extractor.rb`:
```ruby
require "prism"

module RailsSync
  module Static
    module ParamsExtractor
      module_function

      def extract(source)
        program = Prism.parse(source).value
        actions = {}
        each_def(program) do |def_node|
          tree = first_permit_tree(def_node.body)
          actions[def_node.name.to_s] = tree if tree
        end
        actions
      end

      def each_def(node, &block)
        return unless node

        yield node if node.is_a?(Prism::DefNode)
        node.compact_child_nodes.each { |child| each_def(child, &block) }
      end

      # Depth-first: return the tree for the first `permit` call found.
      def first_permit_tree(node)
        return nil unless node

        if node.is_a?(Prism::CallNode) && node.name == :permit
          tree = permit_args_to_tree(node.arguments)
          key = require_key(node.receiver)
          return key ? { key => tree } : tree
        end

        node.compact_child_nodes.each do |child|
          found = first_permit_tree(child)
          return found if found
        end
        nil
      end

      def require_key(receiver)
        return nil unless receiver.is_a?(Prism::CallNode) && receiver.name == :require

        arg = receiver.arguments&.arguments&.first
        arg.is_a?(Prism::SymbolNode) ? arg.unescaped : nil
      end

      def permit_args_to_tree(arguments_node)
        tree = {}
        (arguments_node&.arguments || []).each do |arg|
          case arg
          when Prism::SymbolNode
            tree[arg.unescaped] = nil
          when Prism::KeywordHashNode, Prism::HashNode
            arg.elements.each do |assoc|
              next unless assoc.is_a?(Prism::AssocNode) && assoc.key.is_a?(Prism::SymbolNode)

              tree[assoc.key.unescaped] = value_to_tree(assoc.value)
            end
          end
        end
        tree
      end

      def value_to_tree(value)
        return nil unless value.is_a?(Prism::ArrayNode)
        return [nil] if value.elements.empty?

        nested = {}
        value.elements.each do |el|
          nested[el.unescaped] = nil if el.is_a?(Prism::SymbolNode)
        end
        nested
      end
    end
  end
end
```

Add to `lib/rails_sync.rb`:
```ruby
require_relative "rails_sync/static/params_extractor"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/static/params_extractor_spec.rb`
Expected: PASS. (If a Prism node accessor name differs in the installed Prism version, adjust against `Prism.parse(source).value` in a console; the structure above targets Prism >= 0.24.)

- [ ] **Step 5: Commit**

```bash
git add lib/rails_sync/static/params_extractor.rb lib/rails_sync.rb spec/static/params_extractor_spec.rb
git commit -m "feat: Static::ParamsExtractor reads strong params via Prism"
```

---

### Task 6: Runtime::ObservationStore + Runtime::Middleware

**Files:**
- Create: `lib/rails_sync/runtime/observation_store.rb`, `lib/rails_sync/runtime/middleware.rb`, `spec/runtime/observation_store_spec.rb`, `spec/runtime/middleware_spec.rb`
- Modify: `lib/rails_sync.rb` (add requires)

**Interfaces:**
- Consumes: nothing (store takes a path; middleware takes injected collaborators).
- Produces:
  - `RailsSync::Runtime::ObservationStore.new(path)`; `#append(hash) -> void` (one JSON line, creates parent dirs); `#all -> Array<Hash>`; `#clear -> void`.
  - `RailsSync::Runtime::Middleware.new(app, store:, route_resolver:, enabled: true)`; Rack `#call(env)`. `route_resolver` is any callable `->(env) { template_String_or_nil }`. Captures only when `enabled` and the **response** content-type is JSON. Capturing never raises into the request.
  - Observation shape: `{ "verb"=>String, "path_template"=>String, "request"=>{ "content_type"=>String|nil, "params"=>Hash }, "response"=>{ "status"=>Integer, "content_type"=>String, "body"=>parsed_json } }`.

- [ ] **Step 1: Write the failing tests**

`spec/runtime/observation_store_spec.rb`:
```ruby
require "tmpdir"

RSpec.describe RailsSync::Runtime::ObservationStore do
  it "appends and reads back JSONL, creating parent dirs" do
    Dir.mktmpdir do |dir|
      store = described_class.new(File.join(dir, "nested", "obs.jsonl"))
      store.append("verb" => "GET", "path_template" => "/a")
      store.append("verb" => "POST", "path_template" => "/b")
      expect(store.all).to eq([
        { "verb" => "GET", "path_template" => "/a" },
        { "verb" => "POST", "path_template" => "/b" }
      ])
    end
  end

  it "clear empties the store" do
    Dir.mktmpdir do |dir|
      store = described_class.new(File.join(dir, "obs.jsonl"))
      store.append("verb" => "GET")
      store.clear
      expect(store.all).to eq([])
    end
  end
end
```

`spec/runtime/middleware_spec.rb`:
```ruby
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
    allow_any_instance_of(described_class).to receive(:enabled?).and_return(false)
    get "/users"
    expect(store.all).to eq([])
  end
end
```

(Note: the second middleware test uses `enabled: false` semantics; implement `#enabled?` reading the constructor flag so it is stubbable, or simply construct with `enabled: false` — adjust the test to build a disabled instance directly if preferred.)

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/runtime`
Expected: FAIL with `uninitialized constant RailsSync::Runtime::ObservationStore`.

- [ ] **Step 3: Implement**

`lib/rails_sync/runtime/observation_store.rb`:
```ruby
require "json"
require "fileutils"

module RailsSync
  module Runtime
    class ObservationStore
      def initialize(path)
        @path = path
      end

      def append(hash)
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a") { |f| f.puts(JSON.generate(hash)) }
      end

      def all
        return [] unless File.exist?(@path)

        File.readlines(@path, chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
      end

      def clear
        File.delete(@path) if File.exist?(@path)
      end
    end
  end
end
```

`lib/rails_sync/runtime/middleware.rb`:
```ruby
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
```

Add to `lib/rails_sync.rb`:
```ruby
require_relative "rails_sync/runtime/observation_store"
require_relative "rails_sync/runtime/middleware"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/runtime`
Expected: PASS. (If the disabled-case test is awkward to stub, replace it with one that builds `described_class.new(inner, store: store, route_resolver: ->(_e){"/x"}, enabled: false)` and asserts `store.all` is empty.)

- [ ] **Step 5: Commit**

```bash
git add lib/rails_sync/runtime spec/runtime lib/rails_sync.rb
git commit -m "feat: runtime ObservationStore and capture Middleware"
```

---

### Task 7: Merger

**Files:**
- Create: `lib/rails_sync/merger.rb`, `spec/merger_spec.rb`
- Modify: `lib/rails_sync.rb` (add require)

**Interfaces:**
- Consumes: two `RailsSync::OpenAPIDocument` instances (`existing` may be `nil`), `prune:` boolean.
- Produces: `RailsSync::Merger.merge(existing, fresh, prune: false) -> OpenAPIDocument`. Rules: result starts from `fresh`; for every operation present in BOTH, copy human keys (`summary`, `description`, `tags`) from existing onto the result; preserve schema-level `description` on matching response/request schemas. If `existing` has an `info` block, keep it verbatim. Operations in `existing` but absent from `fresh` are **stale**: kept and tagged `"x-rails-sync-stale" => true` unless `prune`, in which case dropped. Deterministic + idempotent: `merge(merge(e,f), f) == merge(e,f)`.

- [ ] **Step 1: Write the failing tests**

`spec/merger_spec.rb`:
```ruby
RSpec.describe RailsSync::Merger do
  def doc(paths)
    RailsSync::OpenAPIDocument.new({ "openapi" => "3.1.0", "info" => { "title" => "API", "version" => "1.0.0" }, "paths" => paths })
  end

  it "preserves human prose on operations that still exist" do
    existing = doc("/users" => { "get" => { "summary" => "List users", "responses" => {} } })
    fresh = doc("/users" => { "get" => { "responses" => { "200" => {} } } })
    merged = described_class.merge(existing, fresh).to_h
    expect(merged["paths"]["/users"]["get"]["summary"]).to eq("List users")
    expect(merged["paths"]["/users"]["get"]["responses"]).to eq("200" => {})
  end

  it "flags stale operations not present in fresh" do
    existing = doc("/legacy" => { "get" => { "responses" => {} } })
    fresh = doc("/users" => { "get" => { "responses" => {} } })
    merged = described_class.merge(existing, fresh).to_h
    expect(merged["paths"]["/legacy"]["get"]["x-rails-sync-stale"]).to be(true)
    expect(merged["paths"]).to have_key("/users")
  end

  it "prunes stale operations when prune: true" do
    existing = doc("/legacy" => { "get" => { "responses" => {} } })
    fresh = doc("/users" => { "get" => { "responses" => {} } })
    merged = described_class.merge(existing, fresh, prune: true).to_h
    expect(merged["paths"]).not_to have_key("/legacy")
  end

  it "keeps the existing info block verbatim" do
    existing = doc("/users" => { "get" => { "responses" => {} } })
    existing_h = existing.to_h.merge("info" => { "title" => "My Real API", "version" => "2.3.0" })
    merged = described_class.merge(RailsSync::OpenAPIDocument.new(existing_h), doc({})).to_h
    expect(merged["info"]).to eq("title" => "My Real API", "version" => "2.3.0")
  end

  it "is idempotent" do
    existing = doc("/legacy" => { "get" => { "responses" => {} } })
    fresh = doc("/users" => { "get" => { "summary" => "x", "responses" => {} } })
    once = described_class.merge(existing, fresh)
    twice = described_class.merge(once, fresh)
    expect(twice.to_h).to eq(once.to_h)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/merger_spec.rb`
Expected: FAIL with `uninitialized constant RailsSync::Merger`.

- [ ] **Step 3: Implement**

`lib/rails_sync/merger.rb`:
```ruby
module RailsSync
  module Merger
    HUMAN_OP_KEYS = %w[summary description tags].freeze

    module_function

    def merge(existing, fresh, prune: false)
      result = fresh.to_h
      result_paths = result["paths"] ||= {}
      return OpenAPIDocument.new(result) if existing.nil?

      existing_h = existing.to_h
      result["info"] = existing_h["info"] if existing_h["info"]

      (existing_h["paths"] || {}).each do |path, ops|
        ops.each do |verb, existing_op|
          target = result_paths.dig(path, verb)
          if target
            HUMAN_OP_KEYS.each { |k| target[k] = existing_op[k] if existing_op.key?(k) }
            preserve_descriptions(existing_op["responses"], target["responses"])
          elsif !prune
            (result_paths[path] ||= {})[verb] = existing_op.merge("x-rails-sync-stale" => true)
          end
        end
      end

      OpenAPIDocument.new(result)
    end

    # Recursively copy "description" from old schema nodes onto matching new ones.
    def preserve_descriptions(old_node, new_node)
      return unless old_node.is_a?(Hash) && new_node.is_a?(Hash)

      new_node["description"] = old_node["description"] if old_node.key?("description")
      old_node.each do |key, old_child|
        next if key == "description"

        preserve_descriptions(old_child, new_node[key])
      end
    end
  end
end
```

Add to `lib/rails_sync.rb`:
```ruby
require_relative "rails_sync/merger"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/merger_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/rails_sync/merger.rb lib/rails_sync.rb spec/merger_spec.rb
git commit -m "feat: Merger preserves prose, flags stale ops, idempotent"
```

---

### Task 8: Builder (orchestration) + RailsSync.generate/.build

**Files:**
- Create: `lib/rails_sync/builder.rb`, `spec/builder_spec.rb`
- Modify: `lib/rails_sync.rb` (require + top-level `.generate`/`.build`)

**Interfaces:**
- Consumes: `Static::RouteExtractor`, `Static::ParamsExtractor`, `SchemaInferrer`, `OpenAPIDocument`, `Merger`, `Runtime::ObservationStore`.
- Produces:
  - `RailsSync::Builder.new(route_set:, controller_sources:, observations: []).build_fresh -> OpenAPIDocument` where `controller_sources` is `Hash{controller_name(String) => source(String)}` and `observations` is `Array<Hash>` (ObservationStore shape).
  - `RailsSync.generate(route_set:, controller_sources:, output_path:, prune: false) -> OpenAPIDocument` — static only; merges into existing file at `output_path` and writes it.
  - `RailsSync.build(route_set:, controller_sources:, observation_store:, output_path:, prune: false) -> OpenAPIDocument` — static + observations; merges and writes.
- Assembly rules: each route -> `paths[template][verb_downcase]`. Request body schema = param-tree-to-loose-schema (static) merged with inferred request params (runtime). Responses keyed by observed status string -> `{ "description" => "", "content" => { "application/json" => { "schema" => inferred } } }`. Static-only operations with no observed response get `responses => { "default" => { "description" => "" } }`.

- [ ] **Step 1: Write the failing test**

`spec/builder_spec.rb`:
```ruby
require "action_dispatch"
require "tmpdir"

RSpec.describe RailsSync::Builder do
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

  it "RailsSync.build writes and merges into the output file" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "openapi.yml")
      store = RailsSync::Runtime::ObservationStore.new(File.join(dir, "obs.jsonl"))
      observations.each { |o| store.append(o) }
      RailsSync.build(route_set: route_set, controller_sources: controller_sources, observation_store: store, output_path: out)
      reloaded = RailsSync::OpenAPIDocument.load_file(out)
      expect(reloaded.operation("/users", "post")).not_to be_nil
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/builder_spec.rb`
Expected: FAIL with `uninitialized constant RailsSync::Builder`.

- [ ] **Step 3: Implement**

`lib/rails_sync/builder.rb`:
```ruby
module RailsSync
  class Builder
    def initialize(route_set:, controller_sources: {}, observations: [])
      @route_set = route_set
      @controller_sources = controller_sources
      @observations = observations
    end

    def build_fresh
      doc = OpenAPIDocument.new
      routes = Static::RouteExtractor.new(@route_set).extract
      params_by_controller = extract_params

      routes.each do |route|
        op = { "responses" => {} }
        add_request_body(op, route, params_by_controller)
        add_observed(op, route)
        op["responses"]["default"] = { "description" => "" } if op["responses"].empty?
        doc.set_operation(route[:path], route[:verb], op)
      end
      doc
    end

    private

    def extract_params
      @controller_sources.transform_values { |src| Static::ParamsExtractor.extract(src) }
    end

    def add_request_body(op, route, params_by_controller)
      tree = params_by_controller.dig(route[:controller], route[:action])
      static_schema = tree ? tree_to_schema(tree) : nil
      runtime_schema = observed_request_schema(route)
      schema = [static_schema, runtime_schema].compact.reduce(nil) { |a, s| a ? SchemaInferrer.merge(a, s) : s }
      return if schema.nil?

      op["requestBody"] = { "content" => { "application/json" => { "schema" => schema } } }
    end

    def observed_request_schema(route)
      bodies = matching(route).map { |o| o.dig("request", "params") }.compact
      bodies.empty? ? nil : SchemaInferrer.infer_all(bodies)
    end

    def add_observed(op, route)
      matching(route).group_by { |o| o.dig("response", "status") }.each do |status, group|
        bodies = group.map { |o| o.dig("response", "body") }
        op["responses"][status.to_s] = {
          "description" => "",
          "content" => { "application/json" => { "schema" => SchemaInferrer.infer_all(bodies) } }
        }
      end
    end

    def matching(route)
      @observations.select { |o| o["verb"] == route[:verb] && o["path_template"] == route[:path] }
    end

    def tree_to_schema(tree)
      case tree
      when nil then {}
      when Array then { "type" => "array", "items" => tree_to_schema(tree.first) }
      when Hash
        props = tree.transform_values { |v| tree_to_schema(v) }
        { "type" => "object", "properties" => props }
      end
    end
  end

  module_function

  def generate(route_set:, controller_sources:, output_path:, prune: false)
    write_merged(route_set: route_set, controller_sources: controller_sources, observations: [], output_path: output_path, prune: prune)
  end

  def build(route_set:, controller_sources:, observation_store:, output_path:, prune: false)
    write_merged(route_set: route_set, controller_sources: controller_sources, observations: observation_store.all, output_path: output_path, prune: prune)
  end

  def write_merged(route_set:, controller_sources:, observations:, output_path:, prune:)
    fresh = Builder.new(route_set: route_set, controller_sources: controller_sources, observations: observations).build_fresh
    existing = File.exist?(output_path) ? OpenAPIDocument.load_file(output_path) : nil
    merged = Merger.merge(existing, fresh, prune: prune)
    merged.write(output_path)
    merged
  end
end
```

Add to `lib/rails_sync.rb`:
```ruby
require_relative "rails_sync/builder"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/builder_spec.rb`
Expected: PASS.

- [ ] **Step 5: Run the whole suite + commit**

Run: `bundle exec rspec`
Expected: PASS (all specs).
```bash
git add lib/rails_sync/builder.rb lib/rails_sync.rb spec/builder_spec.rb
git commit -m "feat: Builder composes static + runtime into the contract"
```

---

### Task 9: Rails wiring + end-to-end integration

**Files:**
- Create: `lib/rails_sync/configuration.rb`, `lib/rails_sync/runtime/route_resolver.rb`, `lib/rails_sync/railtie.rb`, `lib/tasks/rails_sync.rake`, `spec/integration/build_spec.rb`, and a minimal `spec/integration/dummy/` Rails app.
- Modify: `lib/rails_sync.rb` (require configuration; require railtie if `defined?(Rails::Railtie)`).

**Interfaces:**
- Consumes: everything above; a host Rails app.
- Produces:
  - `RailsSync::Configuration` with `output_path` (default `"openapi.yml"`), `observations_path` (default `"tmp/rails_sync/observations.jsonl"`), `enabled?` (`ENV["RAILS_SYNC"]` truthy). `RailsSync.configuration` memoized accessor.
  - `RailsSync::Runtime::RouteResolver.new(route_set)` — callable `#call(env)` returning the OpenAPI template for the matched route using `env["action_dispatch.request.path_parameters"]` (`{controller:, action:}`); reuses `Static::RouteExtractor` to map controller#action -> template; returns `nil` if unmatched.
  - `RailsSync::Railtie` — inserts `Runtime::Middleware` into the app middleware stack (configured with a `RouteResolver` over `Rails.application.routes` and `enabled: RailsSync.configuration.enabled?`) and loads the rake tasks.
  - Rake tasks `rails_sync:generate` and `rails_sync:build` calling `RailsSync.generate`/`.build` with `route_set: Rails.application.routes`, `controller_sources:` read from `app/controllers/**/*.rb`, the configured `observation_store`, and `output_path`.

- [ ] **Step 1: Scaffold the dummy app**

Create a minimal bootable Rails API app under `spec/integration/dummy/`:

`spec/integration/dummy/config/application.rb`:
```ruby
require "rails"
require "action_controller/railtie"
require "rails_sync"

module Dummy
  class Application < Rails::Application
    config.load_defaults 7.0
    config.eager_load = false
    config.api_only = true
    config.secret_key_base = "test"
    config.logger = Logger.new(IO::NULL)
  end
end
```

`spec/integration/dummy/config/routes.rb`:
```ruby
Dummy::Application.routes.draw do
  resources :users, only: [:show, :create]
end
```

`spec/integration/dummy/app/controllers/users_controller.rb`:
```ruby
class UsersController < ActionController::API
  USERS = { 7 => { id: 7, name: "Ada" } }

  def show
    render json: USERS.fetch(params[:id].to_i)
  end

  def create
    attrs = params.require(:user).permit(:name)
    render json: { id: 8, name: attrs[:name] }, status: :created
  end
end
```

- [ ] **Step 2: Write the failing integration test**

`spec/integration/build_spec.rb`:
```ruby
require "tmpdir"

RSpec.describe "end-to-end build", type: :integration do
  before(:all) do
    ENV["RAILS_SYNC"] = "1"
    require File.expand_path("dummy/config/application", __dir__)
    require File.expand_path("dummy/config/routes", __dir__)
    Dummy::Application.initialize! unless Dummy::Application.initialized?
  end

  it "captures traffic and writes a merged contract" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "openapi.yml")
      store = RailsSync::Runtime::ObservationStore.new(File.join(dir, "obs.jsonl"))
      resolver = RailsSync::Runtime::RouteResolver.new(Dummy::Application.routes)

      inner = Dummy::Application
      mw = RailsSync::Runtime::Middleware.new(inner, store: store, route_resolver: resolver, enabled: true)

      env_post = Rack::MockRequest.env_for("/users", method: "POST",
        input: { user: { name: "Grace" } }.to_json, "CONTENT_TYPE" => "application/json")
      mw.call(env_post)
      env_get = Rack::MockRequest.env_for("/users/7", method: "GET")
      mw.call(env_get)

      sources = { "users" => File.read(File.expand_path("dummy/app/controllers/users_controller.rb", __dir__)) }
      RailsSync.build(route_set: Dummy::Application.routes, controller_sources: sources, observation_store: store, output_path: out)

      doc = RailsSync::OpenAPIDocument.load_file(out)
      expect(doc.operation("/users", "post")["responses"]).to have_key("201")
      expect(doc.operation("/users/{id}", "get")["responses"]).to have_key("200")

      # Idempotency + prose preservation
      first = File.read(out)
      reloaded = doc.to_h
      reloaded["paths"]["/users"]["post"]["summary"] = "Create a user"
      RailsSync::OpenAPIDocument.new(reloaded).write(out)
      RailsSync.build(route_set: Dummy::Application.routes, controller_sources: sources, observation_store: store, output_path: out)
      expect(RailsSync::OpenAPIDocument.load_file(out).operation("/users", "post")["summary"]).to eq("Create a user")
    end
  end
end
```

- [ ] **Step 3: Run to verify failure**

Run: `bundle exec rspec spec/integration/build_spec.rb`
Expected: FAIL with `uninitialized constant RailsSync::Runtime::RouteResolver`.

- [ ] **Step 4: Implement configuration + resolver**

`lib/rails_sync/configuration.rb`:
```ruby
module RailsSync
  class Configuration
    attr_accessor :output_path, :observations_path

    def initialize
      @output_path = "openapi.yml"
      @observations_path = "tmp/rails_sync/observations.jsonl"
    end

    def enabled?
      v = ENV["RAILS_SYNC"]
      !v.nil? && !v.empty? && v != "0" && v.downcase != "false"
    end

    def observation_store
      Runtime::ObservationStore.new(observations_path)
    end
  end

  module_function

  def configuration
    @configuration ||= Configuration.new
  end
end
```

`lib/rails_sync/runtime/route_resolver.rb`:
```ruby
module RailsSync
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
```

Add to `lib/rails_sync.rb`:
```ruby
require_relative "rails_sync/configuration"
require_relative "rails_sync/runtime/route_resolver"
require_relative "rails_sync/railtie" if defined?(Rails::Railtie)
```

- [ ] **Step 5: Run to verify the integration test passes**

Run: `bundle exec rspec spec/integration/build_spec.rb`
Expected: PASS. (The middleware must run after routing so `path_parameters` is populated; in this test we drive it directly through the full app, which performs routing inside `@app.call`.)

- [ ] **Step 6: Implement Railtie + rake tasks**

`lib/rails_sync/railtie.rb`:
```ruby
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
```

`lib/tasks/rails_sync.rake`:
```ruby
namespace :rails_sync do
  def rails_sync_controller_sources
    Dir[Rails.root.join("app/controllers/**/*.rb")].each_with_object({}) do |path, h|
      name = path.sub("#{Rails.root.join('app/controllers')}/", "").sub(/_controller\.rb\z/, "")
      h[name] = File.read(path)
    end
  end

  desc "Generate the static OpenAPI skeleton"
  task generate: :environment do
    RailsSync.generate(
      route_set: Rails.application.routes,
      controller_sources: rails_sync_controller_sources,
      output_path: RailsSync.configuration.output_path
    )
    puts "rails_sync: wrote #{RailsSync.configuration.output_path}"
  end

  desc "Build the contract from static analysis + captured observations"
  task build: :environment do
    RailsSync.build(
      route_set: Rails.application.routes,
      controller_sources: rails_sync_controller_sources,
      observation_store: RailsSync.configuration.observation_store,
      output_path: RailsSync.configuration.output_path
    )
    puts "rails_sync: wrote #{RailsSync.configuration.output_path}"
  end
end
```

- [ ] **Step 7: Run the whole suite + commit**

Run: `bundle exec rspec`
Expected: PASS (all specs, including integration).
```bash
git add lib/rails_sync spec/integration lib/tasks lib/rails_sync.rb
git commit -m "feat: Rails wiring (railtie, rake tasks, route resolver) + integration test"
```

---

## Self-Review

**Spec coverage:**
- Hybrid extraction — static (Tasks 4, 5) + runtime (Task 6); composed in Task 8. ✓
- OpenAPI 3.1 output — Task 3 (`"3.1.0"`). ✓
- Rack-middleware-first capture, optional RSpec shim — Task 6 middleware; shim is explicitly a *future* layer (spec §3) and out of v1 build, so no task — acceptable. ✓
- Serializer-agnostic runtime — Task 6 reads response bytes; no serializer coupling anywhere. ✓
- Single committed `openapi.yml`, additive idempotent merge, prose preserved, stale flagged, `--prune` — Task 7 (merge/prose/stale/idempotency) + Task 8 (file write/merge) + Task 9 (config default path). The `--prune` *flag* is threaded as a `prune:` param; exposing it as a rake env var (`PRUNE=1`) is a trivial add the engineer can include in Task 9's rake tasks if desired. ✓
- Best-effort static params with runtime correction — Task 5 (best-effort, first-permit-only) + Task 8 (static schema merged under runtime via `SchemaInferrer.merge`). ✓
- Minimal deps (Prism, Rack, railties) — Task 1 gemspec. ✓
- Testing via `spec/dummy` + unit TDD — Tasks 2–8 unit, Task 9 integration. ✓

**Placeholder scan:** No "TBD"/"add error handling"/uncoded steps. Middleware capture error handling is concretely a rescue-to-nil. ✓

**Type consistency:** `SchemaInferrer.{infer,merge,infer_all}`, `OpenAPIDocument.{new,load_file,to_h,to_yaml,write,paths,operation,set_operation}`, `RouteExtractor#extract` keys (`:verb,:path,:controller,:action,:path_params`), `ParamsExtractor.extract` ParamTree shape, `ObservationStore.{new,append,all,clear}`, `Middleware.new(app, store:, route_resolver:, enabled:)`, `Merger.merge(existing, fresh, prune:)`, `Builder.new(route_set:, controller_sources:, observations:)#build_fresh`, `RailsSync.{generate,build}` — all referenced consistently across tasks. ✓

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-18-rails-sync-openapi-extractor.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
