require_relative "lib/rails_sync/version"

Gem::Specification.new do |spec|
  spec.name = "rails_sync"
  spec.version = RailsSync::VERSION
  spec.authors = ["dani"]
  spec.email = ["danielsilas23@yahoo.com"]

  spec.summary = "Generate and maintain an OpenAPI 3.1 contract for a Rails JSON API."
  spec.description = <<~DESC.strip
    RailsSync produces and maintains a single committed openapi.yml for a Rails
    JSON API by combining static route/strong-params introspection with runtime
    observation of real responses via a Rack middleware. The result is idempotent,
    preserves hand-written documentation, and is serializer-agnostic.
  DESC
  spec.homepage = "https://github.com/yv-soft/rails-sync"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "lib/tasks/**/*.rake"] + ["README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "prism", ">= 0.24"
  spec.add_dependency "railties", ">= 7.0"
  spec.add_dependency "rack", ">= 2.2"

  spec.add_development_dependency "rails", ">= 7.0"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rack-test", "~> 2.1"
end
