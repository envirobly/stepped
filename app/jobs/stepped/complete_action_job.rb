class Stepped::CompleteActionJob < ActiveJob::Base
  queue_as :default

  def perform(actor, name, status = :succeeded)
    Stepped::Performance.outbound_complete(actor, name, status)
  end
end
