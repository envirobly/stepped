# Generic model for performance tests outside of test env
class Stepped::Actor < ActiveRecord::Base
  stepped_action :live do
    step do |step|
      step.do :sleep
    end

    step do |step, actors|
      step.on actors, :sleep
    end

    step do |step, actors|
      step.on actors, :sleep
    end

    step do |step, actors|
      step.on actors, :sleep
    end
  end

  stepped_action :sleep, outbound: true do
    checksum { Time.now.to_i }

    succeeded do
      update! content: "awake"
    end
  end

  def sleep
    update! content: "sleeping"
    Stepped::CompleteActionJob.perform_later(self, :sleep)
  end
end
