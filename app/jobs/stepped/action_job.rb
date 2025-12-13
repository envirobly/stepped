class Stepped::ActionJob < ActiveJob::Base
  queue_as :default

  def perform(actor, name, *arguments, parent_step: nil)
    root = parent_step.nil?
    action = Stepped::Action.new(actor:, name:, arguments:, root:)
    action.parent_steps << parent_step if parent_step.present?
    action.obtain_lock_and_perform
  end
end
