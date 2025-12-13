module Stepped
  class Engine < ::Rails::Engine
    initializer "stepped.active_record.extensions" do
      ActiveSupport.on_load :active_record do
        include Stepped::Actionable
      end
    end
  end
end
