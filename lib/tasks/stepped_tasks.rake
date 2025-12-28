namespace :stepped do
  desc "Install Stepped Actions"
  task install: "stepped:install:migrations"

  namespace :install do
    desc "Copy Stepped migrations to the host app"
    task migrations: :environment do
      ENV["FROM"] = Stepped::Engine.railtie_name
      Rake::Task["railties:install:migrations"].invoke
    end
  end
end
