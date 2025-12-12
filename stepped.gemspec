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

  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 8.1"

  spec.add_development_dependency "bundler", ">= 2.5"
  spec.add_development_dependency "minitest", ">= 5.0"
  spec.add_development_dependency "rake", ">= 13.0"
end
