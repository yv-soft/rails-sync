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
