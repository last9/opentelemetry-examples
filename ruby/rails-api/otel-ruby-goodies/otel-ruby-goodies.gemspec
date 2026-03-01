# frozen_string_literal: true

require_relative 'lib/otel_ruby_goodies/version'

Gem::Specification.new do |spec|
  spec.name = 'otel-ruby-goodies'
  spec.version = OTelRubyGoodies::VERSION
  spec.authors = ['Last9']
  spec.email = ['engineering@last9.io']

  spec.summary = 'Production helpers for OpenTelemetry Ruby instrumentations.'
  spec.description = 'Reusable OpenTelemetry Ruby patches maintained by Last9.'
  spec.homepage = 'https://github.com/last9/otel-ruby-goodies'
  spec.license = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.1.0'

  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*', 'README.md', 'LICENSE*']
  end

  spec.require_paths = ['lib']

  spec.add_dependency 'opentelemetry-api', '>= 1.0'
  spec.add_dependency 'railties', '>= 7.0'
end
