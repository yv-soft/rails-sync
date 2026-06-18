# RailsContractSync

**Keep an OpenAPI 3.1 contract for your Rails JSON API in sync — automatically.**

RailsContractSync produces and maintains a single committed `openapi.yml` for your Rails API by combining two sources of truth:

- **Static introspection** — reads your routes and `params.require/permit` declarations (via [Prism](https://github.com/ruby/prism)) to lay down the endpoint + request-parameter skeleton, with zero test runs.
- **Runtime observation** — a lightweight Rack middleware records the *actual* JSON responses your app returns (in your test suite, or while you click around in development) and fills in real response schemas.

The two are merged into one committed file that is:

- **Idempotent** — re-run it anytime; the output is byte-stable, so diffs show only real API changes.
- **Prose-preserving** — your hand-written `summary`/`description`/`tags` are never clobbered by a regeneration.
- **Honest** — endpoints you haven't exercised yet are flagged, not faked.

Because the runtime layer reads the response *bytes*, RailsContractSync is **serializer-agnostic** — it doesn't care whether you use ActiveModel::Serializers, Jbuilder, Blueprinter, Alba, or plain `render json:`.

## Why

You changed an endpoint. Now your OpenAPI doc is a lie — until someone remembers to hand-edit it. Hand-written API specs rot; fully manual DSLs are tedious; and pure static analysis can't see what your serializers actually emit at runtime. RailsContractSync splits the difference: static analysis gives you an instant, zero-setup skeleton, and your existing tests (or a few minutes of clicking) supply the real response shapes.

## Installation

Add it to your Gemfile — typically in the development and test groups, since that's where the contract is generated:

```ruby
group :development, :test do
  gem "rails_contract_sync"
end
```

Then:

```bash
bundle install
```

## Usage

Three steps.

### 1. Generate the static skeleton

```bash
bin/rails rails_contract_sync:generate
```

Reads your routes and strong-params and writes `openapi.yml` with paths, HTTP verbs, and request-body parameters. No response schemas yet — that's the next step.

### 2. Capture real responses

Run your app with `RAILS_CONTRACT_SYNC=1` so the capture middleware is active:

```bash
RAILS_CONTRACT_SYNC=1 bundle exec rspec     # capture from your request/system specs
# or
RAILS_CONTRACT_SYNC=1 bin/rails server      # then exercise the app by hand
```

Every JSON response is recorded to `tmp/rails_contract_sync/observations.jsonl`. The middleware only mounts when `RAILS_CONTRACT_SYNC` is set, so it never runs in production by accident.

### 3. Build the full contract

```bash
bin/rails rails_contract_sync:build
```

Infers response schemas from the captured traffic, merges them with the static skeleton **and** with any descriptions you've added to `openapi.yml` by hand, and writes the result back. Commit `openapi.yml`.

Re-run `rails_contract_sync:build` whenever your API changes. Stale endpoints (present in the file but no longer in your routes) are tagged `x-rails-contract-sync-stale: true` rather than silently deleted. Pass `prune: true` to remove them instead.

## What the output looks like

```yaml
openapi: 3.1.0
info:
  title: API
  version: 1.0.0
paths:
  "/users":
    post:
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                user:
                  type: object
                  properties:
                    name:
                      type: string
      responses:
        "201":
          description: ""        # add your own prose here — it survives rebuilds
          content:
            application/json:
              schema:
                type: object
                properties:
                  id: { type: integer }
                  name: { type: string }
                required: [id, name]
  "/users/{id}":
    get:
      responses:
        "200":
          description: ""
          content:
            application/json:
              schema:
                type: object
                properties:
                  id: { type: integer }
                  name: { type: string }
                required: [id, name]
```

Point Swagger UI, `openapi-typescript`, Postman, or any OpenAPI 3.1 tool at this file.

## How it works

| Layer | What it does |
|---|---|
| `Static::RouteExtractor` | Maps `Rails.application.routes` to OpenAPI paths (`/users/:id` → `/users/{id}`). |
| `Static::ParamsExtractor` | Parses controllers with Prism to read `params.require(...).permit(...)` (best-effort). |
| `Runtime::Middleware` | Env-gated Rack middleware; records real request params + response bodies. |
| `SchemaInferrer` | Turns observed JSON into JSON Schema, widening types across observations. |
| `Merger` | Reconciles static + observed + your existing file; preserves prose; idempotent. |

## Configuration

```ruby
RailsContractSync.configuration.output_path        # default: "openapi.yml"
RailsContractSync.configuration.observations_path  # default: "tmp/rails_contract_sync/observations.jsonl"
RailsContractSync.configuration.enabled?           # true when ENV["RAILS_CONTRACT_SYNC"] is truthy
```

You can override defaults in an initializer:

```ruby
# config/initializers/rails_contract_sync.rb
RailsContractSync.configuration.output_path = "docs/openapi.yml"
RailsContractSync.configuration.observations_path = "tmp/api_observations.jsonl"
```

## Scope & limitations (v1)

RailsContractSync is deliberately focused. It does **not** try to do everything:

- **JSON REST controllers only** (`ActionController` / `ActionController::API`). No GraphQL or Grape.
- **Static strong-params reading is best-effort.** It handles literal `permit` arguments; conditional or metaprogrammed params are simply filled in by the runtime layer the first time a request hits that endpoint.
- **Response schemas reflect the traffic you capture.** Coverage equals what your tests or manual usage exercise — an endpoint you never call won't get a response schema.
- **Not in scope (yet):** breaking-change / contract diffing in CI. The committed `openapi.yml` is designed to be the seed for that.

## Development

```bash
bundle install
bundle exec rspec
```

## License

MIT — see [LICENSE](LICENSE).
