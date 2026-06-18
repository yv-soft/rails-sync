require "rails"
require "action_controller/railtie"
require "rails_contract_sync"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 7.0
    config.eager_load = false
    config.api_only = true
    config.secret_key_base = "test"
    config.logger = Logger.new(IO::NULL)
    config.hosts = []
  end
end
