class Stepped::Definition
  attr_reader :actor_class, :action_name, :block,
              :outbound, :timeout, :job,
              :concurrency_key_block, :before_block,
              :checksum_block, :checksum_key_block,
              :steps, :after_callbacks

  AFTER_CALLBACKS = %i[
    cancelled
    timed_out
    succeeded
    failed
  ]

  def initialize(actor_class:, action_name:, outbound: false, timeout: nil, job: nil, block: nil)
    @actor_class = actor_class
    @action_name = action_name.to_s
    @outbound = outbound || job.present?
    @timeout = timeout
    @job = job
    @after_callbacks = []
    @steps = []
    @block = block

    instance_exec &block if block

    if @steps.empty?
      @steps.append generate_step
    end
  end

  def duplicate_as(actor_class)
    self.class.new(actor_class:, action_name:, outbound:, timeout:, job:, block:)
  end

  def before(&block)
    @before_block = block
  end

  def concurrency_key(method = nil, &block)
    @concurrency_key_block = procify method, &block
  end

  def checksum(method = nil, &block)
    @checksum_block = procify method, &block
  end

  def checksum_key(method = nil, &block)
    @checksum_key_block = procify method, &block
  end

  def step(&block)
    @steps.append block
  end

  def prepend_step(&block)
    @steps.prepend block
  end

  AFTER_CALLBACKS.each do |name|
    define_method name do |&block|
      after_callbacks << { name:, block: }
    end
  end

  def after(*statuses, &block)
    statuses = [ :all ] if statuses.empty?
    statuses.each do |status|
      status = status.to_sym
      unless status == :all || AFTER_CALLBACKS.include?(status)
        raise ArgumentError, "'#{status}' must be one of #{AFTER_CALLBACKS}"
      end
      after_callbacks << { name: status, block: }
    end
  end

  private
    def procify(method, &block)
      if method.is_a?(Symbol)
        proc do
          send method
        end
      elsif block_given?
        block
      else
        raise ArgumentError, "Symbol referring to a method to call or a block required"
      end
    end

    def method_call_step_block(method_name)
      proc do |step|
        send method_name, *step.action.arguments
      end
    end

    def job_step_block(job)
      proc do |step|
        job.perform_later step.action
      end
    end

    def generate_step
      if job
        job_step_block job
      else
        method_call_step_block action_name
      end
    end
end
