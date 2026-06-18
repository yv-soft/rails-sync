require_relative "rails_contract_sync/version"
require_relative "rails_contract_sync/schema_inferrer"
require_relative "rails_contract_sync/openapi_document"
require_relative "rails_contract_sync/static/route_extractor"
require_relative "rails_contract_sync/static/params_extractor"
require_relative "rails_contract_sync/runtime/observation_store"
require_relative "rails_contract_sync/runtime/middleware"
require_relative "rails_contract_sync/merger"
require_relative "rails_contract_sync/builder"
require_relative "rails_contract_sync/configuration"
require_relative "rails_contract_sync/runtime/route_resolver"
require_relative "rails_contract_sync/railtie" if defined?(Rails::Railtie)

module RailsContractSync
end
