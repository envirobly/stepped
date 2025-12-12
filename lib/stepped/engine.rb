# frozen_string_literal: true

require "rails/engine"
require "action_dispatch"

module Stepped
  class Engine < ::Rails::Engine
    isolate_namespace Stepped
  end
end
