class Stepped::Step < ActiveRecord::Base
  enum :status, %w[
    pending
    performing
    succeeded
    failed
  ].index_by(&:itself)

  belongs_to :action

  has_and_belongs_to_many :actions, -> { order(id: :asc) }, class_name: "Stepped::Action",
    join_table: :stepped_actions_steps, foreign_key: :action_id, association_foreign_key: :step_id,
    inverse_of: :parent_steps

  scope :incomplete, -> { where(status: %i[ pending performing ]) }

  def perform
    @jobs = []
    if execute_block
      ActiveJob.perform_all_later @jobs
    else
      self.pending_actions_count = 0
      self.status = :failed
    end

    complete! if pending_actions_count.zero?
  end

  def do(action_name, *args)
    on action.actor, action_name, *args
  end

  def on(actors, action_name, *args)
    Array(actors).compact.each do |actor|
      increment :pending_actions_count
      @jobs << Stepped::ActionJob.new(actor, action_name, *args, parent_step: self)
    end

    save!
  end

  def wait(duration)
    increment! :pending_actions_count
    @jobs << Stepped::WaitJob.new(self).set(wait: duration)
  end

  def conclude_job(succeeded = true)
    with_lock do
      raise NoPendingActionsError unless pending_actions_count > 0

      decrement :pending_actions_count
      increment :unsuccessful_actions_count unless succeeded

      if pending_actions_count.zero?
        assign_attributes(completed_at: Time.zone.now, status: determine_status)
      end

      save!
    end

    action.accomplished(self) if pending_actions_count.zero?
  end

  def display_position
    definition_index + 1
  end

  private
    def complete!(status = determine_status)
      update!(completed_at: Time.zone.now, status:)
      action.accomplished self
    end

    def block
      action.definition.steps.fetch(definition_index)
    end

    def execute_block
      context = {
        step_id: id,
        parent_action_id: action_id,
        step_no: definition_index,
        block:
      }
      Stepped.handle_exception(context:) do
        action.actor.instance_exec self, *action.arguments, &block
      end
    end

    def determine_status
      return status unless performing?
      unsuccessful_actions_count > 0 ? :failed : :succeeded
    end

  class NoPendingActionsError < StandardError; end
end
