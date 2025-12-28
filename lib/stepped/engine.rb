module Stepped
  class Engine < ::Rails::Engine
    config.stepped_actions = ActiveSupport::OrderedOptions.new
    config.stepped_actions.handle_exceptions = Rails.env.test? ? [] : [ StandardError ]

    initializer "stepped.active_record.extensions" do
      ActiveSupport.on_load :active_record do
        include Stepped::Actionable
      end
    end
  end
end
