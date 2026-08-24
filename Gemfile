source "https://rubygems.org"

gemspec development_group: :test

# TEMPORARY: cloudstack_client 1.6.0 cannot be used outside of cloudstack-cli.
# It calls ActiveSupport's `present?` on every request, and `require "base64"`
# is a LoadError on Ruby 3.4+. Both are fixed in niwo/cloudstack_client#20.
# Remove this override and pin the gemspec to the release that carries the fix.
gem "cloudstack_client", git: "https://github.com/tas50/cloudstack_client.git",
  branch: "fix-standalone-library-use"

group :docs do
  gem "yard"
end

group :cookstyle do
  gem "cookstyle"
end

group :test do
  gem "rake"
  gem "rspec"
end
