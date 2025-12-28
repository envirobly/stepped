module Stepped::Actionable
  extend ActiveSupport::Concern

  class_methods do
    def stepped_action(name, outbound: false, timeout: nil, job: nil, &block)
      Stepped::Registry.add(self, name, outbound:, timeout:, job:, &block)

      define_method "#{name}_now" do |*arguments|
        Stepped::ActionJob.perform_now(self, name, *arguments)
      end

      define_method "#{name}_later" do |*arguments|
        Stepped::ActionJob.perform_later(self, name, *arguments)
      end
    end

    def prepend_stepped_action_step(name, &step_block)
      Stepped::Registry.prepend_step(self, name, &step_block)
    end

    def after_stepped_action(action_name, *statuses, &block)
      Stepped::Registry.append_after_callback(self, action_name, *statuses, &block)
    end
  end

  def stepped_action_tenancy_key(action_name)
    [ self.class.name, id, action_name ].join("/")
  end

  def complete_stepped_action_now(name, status = :succeeded)
    Stepped::CompleteActionJob.perform_now self, name, status
  end

  def complete_stepped_action_later(name, status = :succeeded)
    Stepped::CompleteActionJob.perform_later self, name, status
  end
end
