module Stepped::TestHelper
  def perform_stepped_actions(only: stepped_job_classes)
    perform_enqueued_jobs_recursively(only:)
    complete_stepped_outbound_performances

    perform_stepped_actions(only:) if Stepped::Performance.any? || enqueued_jobs_with(only:).count > 0
  end

  def assert_stepped_action_job(name, actor = nil)
    jobs_before = enqueued_jobs + performed_jobs
    yield
    jobs = (enqueued_jobs + performed_jobs) - jobs_before
    found = false
    all_actions = []
    jobs.each do |job|
      next unless job["job_class"] == "Stepped::ActionJob"

      job_actor, job_action_name = ActiveJob::Arguments.deserialize job["arguments"]
      all_actions << [ job_actor.to_global_id, job_action_name ].join("#")
      next if found

      found = job_action_name == name
      if found && actor.present?
        actor = eval(actor) if actor.is_a?(String)
        found = job_actor == actor
      end
    end
    assert found, <<~MESSAGE
      Stepped action job for '#{name}' was not enqueued or performed#{actor.respond_to?(:to_debug_id) ? " on #{actor.to_debug_id}" : nil}.
      Actions that were: #{all_actions.join(", ")}
    MESSAGE
  end

  def assert_no_stepped_actions
    jobs_before = enqueued_jobs + performed_jobs
    yield
    jobs = (enqueued_jobs + performed_jobs) - jobs_before
    found = false
    all_actions = []
    jobs.each do |job|
      next unless job["job_class"] == "Stepped::ActionJob"
      found = true
      job_actor, job_action_name = ActiveJob::Arguments.deserialize job["arguments"]
      all_actions << [ job_actor.class.name, job_action_name ].join("#")
    end
    assert_not found, <<~MESSAGE
      Stepped action jobs enqueued or performed: #{all_actions.join(", ")}
    MESSAGE
  end

  def handle_stepped_action_exceptions(only: [ StandardError ])
    was = Rails.configuration.x.stepped_actions.handle_exceptions
    Rails.configuration.x.stepped_actions.handle_exceptions = Array(only)
    yield
  ensure
    Rails.configuration.x.stepped_actions.handle_exceptions = was
  end

  def perform_enqueued_jobs_recursively(only: nil)
    total = 0
    loop do
      batch = perform_enqueued_jobs(only:)
      break if batch == 0
      total += batch
    end
    total
  end

  def stepped_job_classes
    [ Stepped::ActionJob, Stepped::TimeoutJob, Stepped::WaitJob ] + Stepped::Registry.job_classes
  end

  def complete_stepped_outbound_performances
    # Consuming app can redefine
  end
end
