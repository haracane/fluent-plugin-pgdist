source "http://rubygems.org"
# Add dependencies required to use your gem here.
# Example:
#   gem "activesupport", ">= 2.3.5"

# Add dependencies to develop your gem here.
# Include everything needed to run rake, tests, features, etc.

gem "fluentd"
gem "pg"

group :development do
  gem "rspec", "~> 2.12.0"
  gem "yard", "~> 0.8.3"
  gem "redcarpet", "~> 2.2.2"
  gem "rdoc", "~> 3.12"
  gem "bundler"
  gem "jeweler", "~> 1.8.4"
  if RUBY_VERSION <= '1.8.7'
    gem "rcov", "~> 1.0.0"
  else
    gem "simplecov", "~> 0.7.1"
    gem "simplecov-rcov", "~> 0.2.3"
  end
  gem "ci_reporter", "~> 1.8.3"
  gem "flog", "~> 3.2.1"
end
