# frozen_string_literal: true

require_relative "lib/stepped/version"

Gem::Specification.new do |spec|
  spec.name          = "stepped"
  spec.version       = Stepped::VERSION
  spec.authors       = ["Robert Starsi"]
  spec.email         = ["klevo@klevo.sk"]

  spec.summary       = "Stepped Actions orchestrate checksumable and reusable tasks."
  spec.homepage      = "https://github.com/envirobly/stepped"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["app/**/*", "lib/**/*", "README.md", "LICENSE"]

  rails_version = ">= 8.1"
  spec.add_dependency "activerecord", rails_version
  spec.add_dependency "activejob", rails_version
  spec.add_dependency "railties", rails_version
  spec.add_dependency "zeitwerk", "~> 2.6"

  spec.add_development_dependency "bundler", ">= 2.5"
  spec.add_development_dependency "minitest", ">= 5.0"
  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "temping"
end
