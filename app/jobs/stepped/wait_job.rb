class Stepped::WaitJob < ActiveJob::Base
  queue_as :default

  def perform(step)
    step.conclude_job
  end
end
