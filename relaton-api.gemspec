# frozen_string_literal: true

require_relative "lib/relaton/api/version"

Gem::Specification.new do |spec|
  spec.name = "relaton-api"
  spec.version = Relaton::Api::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]
  spec.summary = "Relaton API — Rack reference implementation"
  spec.description = "Config-driven Relaton API server over a dataset directory."
  spec.homepage = "https://github.com/relaton/relaton-api-ruby"
  spec.license = "BSD-2-Clause"
  spec.required_ruby_version = ">= 3.0"
  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.add_dependency "rack", ">= 2.2"
  spec.add_dependency "relaton", "~> 2.1"
  spec.add_development_dependency "rspec"
end
