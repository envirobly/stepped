# Stepped Actions

Rails engine for orchestrating complex action trees.

## Features

* Checksums allow action reuse during performance or after successful completion, by other actions.
* Build in queuing and superseding with sensible defaults for orchestration systems.
* Support for outbound completion of actions (an event from another system for example).

## Installation
Add this line to your application's Gemfile:

```ruby
gem "stepped"
```

And then execute:
```bash
bundle install
bin/rails stepped:install
bin/rails db:migrate
```

## Development

### Test suite

```sh
bin/rails db:test:prepare
bin/rails test
```

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
