# Stepped Actions

Stepped is a Rails engine for orchestrating complex workflows as a tree of actions. Each action is persisted, runs through Active Job, and can fan out into more actions (or waits) while keeping the parent action moving step-by-step as dependencies complete.

The core ideas are:

- **Action trees**: define a root action with multiple steps; each step can enqueue more actions and the step completes only once all the actions within it complete.
- **Concurrency lanes**: actions with the same `concurrency_key` share a `Stepped::Performance`, so only one runs at a time while others queue up (with automatic superseding of older queued work).
- **Reuse**: optional `checksum` lets Stepped skip work that is already achieved, or share a currently-performing action with multiple parents.
- **Outbound completion**: actions can be marked outbound (or implemented as a job) and completed later by an external event.

## Installation

Add Stepped to your application (Rails `>= 8.1.1`):

```ruby
gem "stepped"
```

Then install and run the migrations:

```bash
bundle install
bin/rails stepped:install
bin/rails db:migrate
```

## Quick start

Stepped hooks into Active Record automatically, so any model can declare actions.

If you define an action without steps, Stepped generates a single step that calls the instance method with the same name:

```ruby
class Car < ApplicationRecord
  stepped_action :drive

  def drive(miles)
    update!(mileage: mileage + miles)
  end
end

car = Car.find(1)
car.drive_later(5) # enqueues Stepped::ActionJob
car.drive_now(5)   # runs synchronously (still uses the Stepped state machine)
```

Calling `*_now`/`*_later` creates a `Stepped::Action` and a `Stepped::Step` record behind the scenes. If the action finishes immediately, the associated `Stepped::Performance` (the concurrency “lane”) is created and destroyed within the same run. If the action is short-circuited (for example, cancelled/completed in `before`, or skipped due to a matching achievement), Stepped returns an action instance but does not create any database rows.

## Concepts

An action is represented by `Stepped::Action` (statuses include `pending`, `performing`, `succeeded`, `failed`, `cancelled`, `superseded`, `timed_out`, and `deadlocked`). Each action executes one step at a time; steps are stored in `Stepped::Step` and complete when all of their dependencies finish.

Actions that share a `concurrency_key` are grouped under a `Stepped::Performance`. A performance behaves like a single-file queue: the current action performs, later actions wait as `pending`, and when the current action completes the performance advances to the next incomplete action.

If you opt into reuse, successful actions write a `Stepped::Achievement` keyed by `checksum`. When an action is invoked again with the same `checksum`, Stepped can skip the work entirely.

## Defining actions

Define an action on an Active Record model with `stepped_action`. The block is a small DSL that lets you specify steps, hooks, and keys:

```ruby
class Car < ApplicationRecord
  stepped_action :visit do
    step do |step, location|
      step.do :change_location, location
    end

    succeeded do
      update!(last_visited_at: Time.current)
    end
  end

  def change_location(location)
    update!(location:)
  end
end
```

### Steps and action trees

Each `step` block runs in the actor’s context (`self` is the model instance) and receives `(step, *arguments)`. Inside a step you typically enqueue more actions:

```ruby
stepped_action :park do
  step do
    honk
  end

  step do |step, miles|
    step.do :honk
    step.on [self, nil], :drive, miles
  end
end
```

`step.do` is shorthand for “run another action on the same actor”. `step.on` accepts a single actor or an array of actors; `nil` values are ignored. If a step enqueues work, the parent action will remain `performing` until those child actions finish and report back.

To deliberately fail a step without raising, set `step.status = :failed` inside the step body.

The code within the `step` block runs within the model instance context. Therefore you have flexibility to write any model code within this block, not just invoking actions.

### Waiting

Steps can also enqueue a timed wait:

```ruby
stepped_action :stopover do
  step { |step| step.wait 5.seconds }
  step { honk }
end
```

### Before hooks and argument mutation

`before` runs once, before any steps are performed. It can mutate `action.arguments`, or cancel/complete the action early:

```ruby
stepped_action :multiplied_drive do
  before do |action, distance|
    action.arguments = [distance * 2]
  end

  step do |step, distance|
    step.do :drive, distance
  end
end
```

The checksum (if you define one) is computed after `before`, so it sees the updated arguments.

### After callbacks

After callbacks run when the action is completed. You can attach them inline (`succeeded`, `failed`, `cancelled`, `timed_out`) or later from elsewhere with `after_stepped_action`:

```ruby
Car.stepped_action :drive, outbound: true do
  after :cancelled, :failed, :timed_out do
    honk
  end
end

Car.after_stepped_action :drive, :succeeded do |action, miles|
  Rails.logger.info("Drove #{miles} miles")
end
```

If an after callback raises and you’ve configured Stepped to handle that exception class, the action status is preserved but the callback is counted as failed and the action will not grant an achievement.

## Concurrency, queueing, and superseding

Every action runs under a `concurrency_key`. Actions with the same key share a performance and therefore run one-at-a-time, in order.

By default, the key is scoped to the actor and action name (for example `Car/123/visit`). You can override it with `concurrency_key` to coordinate across records or across different actions:

```ruby
stepped_action :recycle, outbound: true do
  concurrency_key { "Car/maintenance" }
end

stepped_action :paint, outbound: true do
  concurrency_key { "Car/maintenance" }
end
```

While one action is `performing`, later actions with the same key are queued as `pending`. If multiple pending actions build up, Stepped supersedes older pending actions in favor of the newest one, and transfers any parent-step dependencies to the newest action so waiting steps don’t get stuck.

Stepped also protects you from deadlocks: if a descendant action tries to join the same `concurrency_key` as one of its ancestors, it is marked `deadlocked` and its parent step will fail.

## Checksums and reuse (Achievements)

Reuse is opt-in per action via `checksum`. When a checksum is present, Stepped stores the last successful checksum in `Stepped::Achievement` under `checksum_key` (which defaults to the action’s tenancy key).

```ruby
stepped_action :visit do
  checksum { |location| location }

  step do |step, location|
    step.do :change_location, location
  end
end
```

With a checksum in place:

1. If you invoke an action while an identical checksum is already performing under the same concurrency lane, Stepped returns the existing performing action and attaches the new parent step to it.
2. If an identical checksum has already succeeded (an achievement exists), Stepped returns a `succeeded` action immediately without creating new records.
3. If the checksum changes, Stepped performs the action and updates the stored achievement to the new checksum.

Use `checksum_key` to control the scope of reuse. Returning an array joins parts with `/`:

```ruby
checksum_key { ["Car", "visit"] } # shared across all cars
```

## Outbound actions and external completion

An outbound action runs its steps but does not complete automatically when the final step finishes. It stays `performing` until you explicitly complete it (for example, from a webhook handler or another system):

```ruby
stepped_action :charge_card, outbound: true do
  step do |step, amount_cents|
    # enqueue calls to external systems here
  end
end

user.charge_card_later(1500)
user.complete_stepped_action_later(:charge_card, :succeeded)
```

Under the hood, completion forwards to the current outbound action for that actor+name and advances its performance queue.

## Job-backed actions

If you prefer to implement an action as an Active Job, declare it with `job:`. Job-backed actions are treated as outbound and are expected to call `action.complete!` when finished:

```ruby
class TowJob < ActiveJob::Base
  def perform(action)
    car = action.actor
    location = action.arguments.first
    car.update!(location:)

    action.complete!
  end
end

class Car < ApplicationRecord
  stepped_action :tow, job: TowJob
end
```

You can extend existing actions (including job-backed ones) by prepending steps:

```ruby
Car.prepend_stepped_action_step :tow do
  honk
end
```

## Timeouts

Set `timeout:` to enqueue a `Stepped::TimeoutJob` when the action starts. If the action is still `performing` after the timeout elapses, it completes as `timed_out`:

```ruby
stepped_action :change_location, outbound: true, timeout: 5.seconds
```

Timeouts propagate through the tree: a timed-out nested action fails its parent step, which fails the parent action.

## Exception handling

Stepped can either raise exceptions (letting your job backend retry) or treat specific exception classes as handled and turn them into action failure.

Configure the handled exception classes in your application:

```ruby
# config/application.rb (or an environment file)
config.x.stepped_actions.handle_exceptions = [StandardError]
```

When an exception is handled, Stepped reports it via `Rails.error.report` and marks the action/step as `failed` instead of raising.

## Testing

Stepped ships with `Stepped::TestHelper` (require `"stepped/test_helper"`) which builds on Active Job’s test helpers to make it easy to drain the full action tree.

```ruby
# test/test_helper.rb
require "stepped/test_helper"

class ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Stepped::TestHelper

  # If your workflows include outbound actions, complete them here so
  # `perform_stepped_actions` can fully drain the tree.
  def complete_stepped_outbound_performances
    Stepped::Performance.outbounds.includes(:action).find_each do |performance|
      action = performance.action
      Stepped::Performance.outbound_complete(action.actor, action.name, :succeeded)
    end
  end
end
```

In a test, you can perform Stepped jobs recursively:

```ruby
car.visit_later("London")
perform_stepped_actions
```

To test failure behavior without bubbling exceptions, you can temporarily mark exception classes as handled:

```ruby
handle_stepped_action_exceptions(only: [StandardError]) do
  car.visit_now("London")
end
```

## Development

Run the test suite:

```sh
bin/rails db:test:prepare
bin/rails test
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
