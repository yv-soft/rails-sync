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
