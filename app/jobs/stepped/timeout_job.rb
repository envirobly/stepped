class Stepped::TimeoutJob < ActiveJob::Base
  queue_as :default

  def perform(action)
    return unless action.performing?

    if action.started_at < action.timeout.ago
      action.complete!(:timed_out)
    end
  end
end
