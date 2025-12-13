module Stepped
  class Engine < ::Rails::Engine
    initializer "stepped.active_record.extensions" do
      ActiveSupport.on_load :active_record do
        include Stepped::Actionable
      end
    end

    rake_tasks do
      load File.expand_path("../tasks/stepped_tasks.rake", __dir__)
    end
  end
end
