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
  spec.license       = 'Apache-2.0'

  spec.files         = `git ls-files`.split($/)
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'test-kitchen', '>= 1.0.0', "< 3"
  spec.add_dependency 'fog-cloudstack', '~> 0.1.0'
end
