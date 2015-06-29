# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kitchen/driver/cloudstack_version'

Gem::Specification.new do |spec|
  spec.name          = 'kitchen-cloudstack'
  spec.version       = Kitchen::Driver::CLOUDSTACK_VERSION
  spec.authors       = ['Jeff Moody']
  spec.email         = ['fifthecho@gmail.com']
  spec.description   = %q{A Test Kitchen Driver for Apache CloudStack}
  spec.summary       = %q{Provides an interface for Test Kitchen to be able to run jobs against an Apache CloudStack cloud.}
  spec.homepage      = 'https://github.com/test-kitchen/kitchen-cloudstack'
  spec.license       = 'Apache 2.0'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = []
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'test-kitchen', '~> 1.0', '>= 1.0.0'
  spec.add_dependency 'fog', '~> 1.23', '>= 1.23.0'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake', '~> 0'

  spec.add_development_dependency 'cane', '~> 2'
  spec.add_development_dependency 'tailor', '~> 1'
  spec.add_development_dependency 'countloc', '~> 0'
  spec.add_development_dependency 'pry', '~> 0'
end
