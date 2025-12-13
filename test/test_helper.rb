# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
require "rails/test_help"
require "temping"

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end

module Stepped
  class TestCase < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    teardown { Temping.teardown }

    def perform_stepped_actions(only: stepped_job_classes)
      perform_enqueued_jobs_recursively(only:)

      perform_stepped_actions(only:) if Stepped::Performance.any? || enqueued_jobs_with(only:).count > 0
    end

    def stepped_job_classes
      [ Stepped::ActionJob, Stepped::TimeoutJob, Stepped::WaitJob ] + Stepped::Registry.job_classes
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

    def handle_stepped_action_exceptions(only: [ StandardError ])
      was = Rails.configuration.x.stepped_actions.handle_exceptions
      Rails.configuration.x.stepped_actions.handle_exceptions = Array(only)
      yield
    ensure
      Rails.configuration.x.stepped_actions.handle_exceptions = was
    end
  end

  class IntegrationTest < ActionDispatch::IntegrationTest
    teardown { Temping.teardown }
  end
end
