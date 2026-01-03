require_relative "lib/stepped/version"

Gem::Specification.new do |spec|
  spec.name        = "stepped"
  spec.version     = Stepped::VERSION
  spec.authors     = [ "Robert Starsi" ]
  spec.email       = [ "klevo@klevo.sk" ]
  spec.homepage    = "https://github.com/envirobly/stepped"
  spec.summary     = "Rails engine for orchestrating complex action trees."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/envirobly/stepped"
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.1.1"
  spec.add_development_dependency "temping"
  spec.add_development_dependency "minitest", "~> 6.0" # Version 6 seems to break `rails test` at the moment (no tests run)
end
