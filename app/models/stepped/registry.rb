class Stepped::Registry
  @job_classes = Concurrent::Array.new
  @definitions = Concurrent::Hash.new

  class << self
    attr_reader :job_classes, :definitions

    def key(klass)
      "#{klass.name}/#{klass.object_id}"
    end

    def add(actor_class, action_name, outbound: false, timeout: nil, job: nil, &block)
      if job && @job_classes.exclude?(job)
        @job_classes.push job
      end

      add_definition actor_class, action_name, Stepped::Definition.new(
        actor_class:,
        action_name:,
        outbound:,
        timeout:,
        job:,
        block:
      )
    end

    def add_definition(actor_class, action_name, definition)
      class_key = key actor_class
      @definitions[class_key] ||= Concurrent::Hash.new
      @definitions[class_key][action_name.to_s] = definition
    end

    def prepend_step(actor_class, action_name, &step_block)
      definition = find_or_add actor_class, action_name

      unless definition.actor_class == actor_class
        definition = add_definition actor_class, action_name, definition.duplicate_as(actor_class)
      end

      definition.prepend_step(&step_block)
    end

    def append_after_callback(actor_class, action_name, *statuses, &block)
      definition = find_or_add actor_class, action_name

      unless definition.actor_class == actor_class
        definition = add_definition actor_class, action_name, definition.duplicate_as(actor_class)
      end

      definition.after(*statuses, &block)
    end

    def find(actor_class, action_name)
      actor_class.ancestors.each do |ancestor|
        definition = @definitions.dig key(ancestor), action_name.to_s
        return definition if definition
      end

      nil
    end

    def find_or_add(actor_class, action_name)
      find(actor_class, action_name) || add(actor_class, action_name)
    end
  end
end
