require "stepped/version"
require "stepped/engine"

module Stepped
  def self.table_name_prefix
    "stepped_"
  end

  def self.handle_exception(context: {})
    yield
    true
  rescue StandardError => e
    raise unless Rails.configuration.x.stepped_actions.handle_exceptions.any? { e.class <= _1 }
    Rails.error.report(e, handled: false, context:)
    false
  end

  def self.checksum(value)
    return if value.nil?
    Digest::SHA256.hexdigest JSON.dump(value)
  end
end
