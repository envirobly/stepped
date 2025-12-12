# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
app_root = File.expand_path("../app", __dir__)
if Dir.exist?(app_root)
  Dir.children(app_root).each do |component_dir|
    loader.push_dir(File.join(app_root, component_dir))
  end
end
loader.setup

module Stepped
end

ActiveSupport.on_load(:active_record) do
  include Stepped::ActiveRecordExtension
end
