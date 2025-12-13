class Stepped::Performance < ActiveRecord::Base
  self.filter_attributes = []

  belongs_to :action
  has_many :actions, -> { order(:id) }, dependent: :nullify

  scope :outbounds, -> { joins(:action).where(action: { outbound: true }) }

  before_save -> { self.outbound_complete_key = action.outbound_complete_key }

  class << self
    def obtain_for(action)
      transaction(requires_new: true) do
        lock.
          create_with(action:).
          find_or_create_by!(concurrency_key: action.concurrency_key).
          share_with(action)
      end
    end

    def outbound_complete(actor, name, status = :succeeded)
      outbound_complete_key = actor.stepped_action_tenancy_key name

      transaction(requires_new: true) do
        lock.find_by(outbound_complete_key:)&.forward(status:)
      end
    end

    def complete_action(action, status)
      transaction(requires_new: true) do
        lock.find_by(concurrency_key: action.concurrency_key)&.forward(action, status:)
      end
    end
  end

  def forward(completing_action = self.action, status: :succeeded)
    completing_action.finalize_complete status

    return unless completing_action == action

    if next_action = actions.incomplete.first
      update!(action: next_action)
      next_action.perform if next_action.pending?
    else
      destroy!
    end
  end

  def share_with(candidate)
    # Secondary check of this kind here within a performance lock
    # prevents race conditions between the first check and obtaining the lock,
    # while the first check in Action#obtain_lock_and_perform speeds things up.
    Stepped::Achievement.raise_if_exists_for?(candidate)

    if candidate.descendant_of?(action)
      return candidate.tap(&:deadlock!)
    end

    if candidate.checksum.present?
      actions.excluding(candidate).each do |action|
        if action.achieves?(candidate)
          candidate.copy_parent_steps_to action
          return action
        end
      end
    end

    other_pending_actions.each { _1.supersede_with(candidate) }
    candidate.tap { _1.update_performance(self) }
  end

  private
    def other_pending_actions
      actions.pending.excluding(action)
    end
end
