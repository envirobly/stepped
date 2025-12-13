class Stepped::Action < ActiveRecord::Base
  self.filter_attributes = []

  STATUSES = %w[
    pending
    performing
    succeeded
    superseded
    cancelled
    failed
    timed_out
    deadlocked
  ].freeze

  enum :status, STATUSES.index_by(&:itself)

  serialize :arguments, coder: Stepped::Arguments

  belongs_to :actor, polymorphic: true
  belongs_to :performance, optional: true

  has_many :steps, -> { order(id: :asc) }, dependent: :destroy

  has_and_belongs_to_many :parent_steps, class_name: "Stepped::Step",
    join_table: :stepped_actions_steps, foreign_key: :step_id, association_foreign_key: :action_id,
    inverse_of: :actions

  scope :roots, -> { where(root: true) }
  scope :outbounds, -> { where(outbound: true) }
  scope :incomplete, -> { where(status: %i[ pending performing ]) }

  KEYS_JOINER = "/"

  def obtain_lock_and_perform
    apply_definition
    run_before_chain

    if completed?
      propagate_completion_to_parent_steps
      return self
    end

    set_checksum

    Stepped::Achievement.raise_if_exists_for?(self)
    Stepped::Performance.obtain_for(self)
  rescue Stepped::Achievement::ExistsError
    self.status = :succeeded
    propagate_completion_to_parent_steps
    self
  end

  def update_performance(performance)
    self.performance = performance
    perform if pending? && (performance.action == self)
    save!
  end

  def perform
    update! status: :performing, started_at: Time.zone.now

    Stepped::Achievement.erase_of self

    ActiveRecord.after_all_transactions_commit do
      perform_current_step
      Stepped::TimeoutJob.set(wait: timeout).perform_later(self) if timeout?
    end
  end

  def definition
    @definition = Stepped::Registry.find_or_add actor.class, name
  end

  def cancel
    self.status = :cancelled
  end

  def complete
    self.status = :succeeded
  end

  def supersede_with(action)
    update! completed_at: Time.zone.now, status: :superseded
    copy_parent_steps_to action
  end

  def achieves?(action)
    checksum_key == action.checksum_key && checksum == action.checksum
  end

  def copy_parent_steps_to(action)
    raise ArgumentError, "Can't copy_parent_steps_to self" if action == self

    parent_steps.each do |step|
      transaction(requires_new: true) do
        action.parent_steps << step
      end
    rescue ActiveRecord::RecordNotUnique
      action.reload
    end
  end

  def perform_current_step
    steps.create!(
      definition_index: current_step_index,
      started_at: Time.zone.now,
      status: :performing
    ).perform
  end

  def compute_concurrency_key
    run_definition_block :concurrency_key_block
  end

  def compute_checksum_key
    run_definition_block :checksum_key_block
  end

  def outbound_complete_key
    outbound? ? tenancy_key : nil
  end

  def accomplished(step)
    if step.failed?
      complete! :failed
    elsif more_steps_to_do?
      increment :current_step_index
      save!
      perform_current_step
    elsif !outbound?
      complete!
    end
  end

  def safe_actor
    actor
  rescue ActiveRecord::SubclassNotFound
  end

  def actor_becomes_base
    safe_actor&.becomes actor_type.constantize
  end

  def short_checksum
    checksum.to_s[0..7]
  end

  def timeout?
    timeout_seconds.present?
  end

  def compute_timeout
    if definition.timeout.is_a?(Symbol)
      actor.send(definition.timeout)
    else
      definition.timeout
    end
  end

  def cancellable?
    pending? || performing?
  end

  def complete!(status = :succeeded)
    Stepped::Performance.complete_action self, status
  end

  def finalize_complete(status)
    self.status = status
    execute_after_complete_callbacks
    update!(completed_at: Time.zone.now, performance: nil)
    Stepped::Achievement.grand_to(self) if succeeded_including_callbacks? && checksum.present?

    propagate_completion_to_parent_steps
  end

  def deadlock!
    e = Deadlock.new "#{name} on #{actor.class.name}/#{actor.id}"
    handled = Rails.configuration.x.stepped_actions.handle_exceptions.any? { e.class <= _1 }
    raise e unless handled

    Rails.error.report(e, handled:)
    self.status = :deadlocked
    propagate_completion_to_parent_steps
  end

  def descendant_of?(action)
    parent_steps.any? do |step|
      return true if step.action_id == action.id
      step.action.descendant_of?(action)
    end
  end

  def completed?
    cancelled? || succeeded? || superseded? || failed? || timed_out? || deadlocked?
  end

  def propagated_touch
    touch
    parent_steps.each { _1.action.propagated_touch }
  end

  def apply_definition
    return if definition.nil?
    self.outbound = definition.outbound
    self.concurrency_key = compute_concurrency_key
    self.checksum_key = compute_checksum_key
    self.job = definition.job
    self.timeout_seconds = compute_timeout
  end

  def timeout
    timeout_seconds.seconds
  end

  def propagate_completion_to_parent_steps
    ActiveRecord.after_all_transactions_commit do
      parent_steps.each do |step|
        step.conclude_job(succeeded_including_callbacks?)
      end
    end
  end

  def succeeded_including_callbacks?
    succeeded? && after_callbacks_failed_count.nil?
  end

  class Deadlock < StandardError; end

  private
    def tenancy_key
      actor.stepped_action_tenancy_key name
    end

    def run_before_chain
      return if failed?

      if before_block = definition.before_block
        fail_on_exception do
          actor.instance_exec self, *arguments, &before_block
        end
      end
    end

    def fail_on_exception(&block)
      unless Stepped.handle_exception(context: { block: }, &block)
        self.status = :failed
      end
    end

    def run_definition_block(method)
      if block = definition.public_send(method)
        result = actor.instance_exec(*arguments, &block)

        return tenancy_key if result.blank?

        result.is_a?(Array) ? result.join(KEYS_JOINER) : result.to_s
      else
        tenancy_key
      end
    end

    def set_checksum
      if block = definition.checksum_block
        value = actor.instance_exec(*arguments, &block)
        self.checksum = Stepped.checksum value
      end
    end

    def execute_after_complete_callbacks
      return true if definition.nil?

      definition.after_callbacks.each do |callback|
        next true unless callback.fetch(:name).in?([ status.to_sym, :all ])

        context = { action: to_global_id, callback: callback.inspect }

        succeeded = Stepped.handle_exception(context:) do
          actor.instance_exec self, *arguments, &callback.fetch(:block)
        end

        if succeeded
          increment :after_callbacks_succeeded_count
        else
          increment :after_callbacks_failed_count
        end
      end
    end

    def more_steps_to_do?
      definition.steps.size > (current_step_index + 1)
    end
end
