# frozen_string_literal: true

require "active_support/lazy_load_hooks"
require_relative "stepped/version"
require_relative "stepped/active_record_extension"
require_relative "stepped/engine"

module Stepped
end

ActiveSupport.on_load(:active_record) do
  include Stepped::ActiveRecordExtension
end
