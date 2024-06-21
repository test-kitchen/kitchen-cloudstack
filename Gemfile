source "https://rubygems.org"

# Specify your gem"s dependencies in kitchen-vagrant.gemspec
gemspec

group :test do
  gem "rake"
  gem "kitchen-inspec"
  gem "rspec", "~> 3.2"
  gem 'cane', '~> 3'
  gem 'tailor', '~> 1'
  gem 'countloc'
end

group :debug do
  gem "pry"
end

group :chefstyle do
  gem "chefstyle", "2.2.3"
end
