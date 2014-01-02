# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kitchen/driver/cloudstack_version'

Gem::Specification.new do |spec|
  spec.name          = 'kitchen-cloudstack'
  spec.version       = Kitchen::Driver::CLOUDSTACK_VERSION
  spec.authors       = ['Jeff Moody']
  spec.email         = ['fifthecho@gmail.com']
  spec.description   = %q{A Test Kitchen Driver for Cloudstack}
  spec.summary       = spec.description
  spec.homepage      = 'https://github.com/fifthecho/kitchen-cloudstack'
  spec.license       = 'Apache 2.0'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = []
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'test-kitchen', '>= 1.0.0'
  spec.add_dependency 'fog', ">=1.15.0"
  spec.add_dependency 'net-ssh-multi'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake'

  spec.add_development_dependency 'cane'
  spec.add_development_dependency 'tailor'
  spec.add_development_dependency 'countloc'
  spec.add_development_dependency 'pry'
end
