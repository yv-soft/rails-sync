namespace :rails_contract_sync do
  def rails_contract_sync_controller_sources
    Dir[Rails.root.join("app/controllers/**/*.rb").to_s].each_with_object({}) do |path, h|
      name = path.sub("#{Rails.root.join('app/controllers')}/", "").sub(/_controller\.rb\z/, "")
      h[name] = File.read(path)
    end
  end

  desc "Generate the static OpenAPI skeleton"
  task generate: :environment do
    sources = rails_contract_sync_controller_sources
    output = RailsContractSync.configuration.output_path

    result = RailsContractSync.generate(
      route_set: Rails.application.routes,
      controller_sources: sources,
      output_path: output
    )

    paths = result.paths.keys
    puts "rails_contract_sync: wrote #{output} (#{paths.size} paths from #{sources.size} controllers)"
  end

  desc "Build the contract from static analysis + captured observations"
  task build: :environment do
    sources = rails_contract_sync_controller_sources
    store = RailsContractSync.configuration.observation_store
    output = RailsContractSync.configuration.output_path
    observations = store.all

    result = RailsContractSync.build(
      route_set: Rails.application.routes,
      controller_sources: sources,
      observation_store: store,
      output_path: output
    )

    paths = result.paths.keys
    puts "rails_contract_sync: wrote #{output} (#{paths.size} paths, #{observations.size} observations, #{sources.size} controllers)"
    if observations.empty?
      puts "rails_contract_sync: hint — run your test suite with RAILS_CONTRACT_SYNC=1 to capture response observations"
    end
  end
end
