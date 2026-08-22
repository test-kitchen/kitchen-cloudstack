lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "kitchen/driver/cloudstack_version"

Gem::Specification.new do |spec|
  spec.name = "kitchen-cloudstack"
  spec.required_ruby_version = ">= 3.1"
  spec.version       = Kitchen::Driver::CLOUDSTACK_VERSION
  spec.authors       = ["Jeff Moody"]
  spec.email         = ["fifthecho@gmail.com"]
  spec.description   = %q{A Test Kitchen Driver for Apache CloudStack}
  spec.summary       = %q{Provides an interface for Test Kitchen to be able to run jobs against an Apache CloudStack cloud.}
  spec.homepage      = "https://github.com/test-kitchen/kitchen-cloudstack"
  spec.license       = "Apache-2.0"

  spec.files         = `git ls-files`.split($/).grep(/LICENSE|^lib/)
  spec.require_paths = ["lib"]

  spec.metadata = {
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{spec.homepage}/blob/main/README.md",
    "source_code_uri" => spec.homepage,
    "rubygems_mfa_required" => "true",
  }

  spec.add_dependency "test-kitchen", ">= 3.0", "< 5"
  spec.add_dependency "fog-cloudstack", "~> 0.1.0"

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"

  spec.add_development_dependency "pry"
end
