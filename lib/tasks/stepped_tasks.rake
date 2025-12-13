namespace :stepped do
  desc "Install Stepped migrations into the host app"
  task install: "stepped:install:migrations"

  namespace :install do
    desc "Copy Stepped migrations to the host app"
    task migrations: :environment do
      previous_from = ENV["FROM"]
      ENV["FROM"] = Stepped::Engine.railtie_name
      Rake::Task["railties:install:migrations"].invoke
      ENV["FROM"] = previous_from
      Rake::Task["railties:install:migrations"].reenable
    end
  end
end
