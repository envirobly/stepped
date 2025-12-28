require "active_job/arguments"

class Stepped::Arguments
  class << self
    def load(serialized_arguments)
      return if serialized_arguments.nil?

      ActiveJob::Arguments.deserialize serialized_arguments
    end

    def dump(arguments)
      ActiveJob::Arguments.serialize arguments
    end
  end
end
