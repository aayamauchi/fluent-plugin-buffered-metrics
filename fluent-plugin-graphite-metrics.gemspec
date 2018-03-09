# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.name          = 'fluent-plugin-graphite-metrics'
  gem.version       = ENV.key?('RUBYGEM_VERSION') ? ENV['RUBYGEM_VERSION'] : '0.0.1'
  gem.authors       = ['Alex Yamauchi']
  gem.email         = ['oss@hotschedules.com']
  gem.homepage      = 'https://github.com/hotscheluds/fluent-plugin-graphite-metrics'
  gem.description   = %q{Fluentd plugin derive metrics and outputs to Graphite/Carbon}
  gem.summary       = %q{Fluentd plugin derive metrics and outputs to Graphite/Carbon.}
  gem.homepage      = 'https://github.com/hotschedules/fluent-plugin-graphite-metrics'
  gem.license       = 'Apache-2.0'
  gem.add_runtime_dependency 'fluentd', '>= 0.10.0'
  gem.files         = `git ls-files`.split("\n")
  gem.executables   = gem.files.grep(%r{^bin/}) { |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']
  gem.signing_key   = File.expand_path( ENV.key?('RUBYGEM_SIGNING_KEY') ? ENV['RUBYGEM_SIGNING_KEY'] : '~/certs/oss@hotschedules.com.key' ) if $0 =~ /\bgem[\.0-9]*\z/
  gem.cert_chain    = %w[certs/oss@hotschedules.com.cert]
end
