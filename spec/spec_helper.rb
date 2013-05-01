# coding: utf-8
if RUBY_VERSION <= '1.8.7'
else
  require "simplecov"
  require "simplecov-rcov"
  SimpleCov.formatter = SimpleCov::Formatter::RcovFormatter
  SimpleCov.start
end

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "..", "lib"))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require "rspec"
require "tempfile"
require "logger"
require "fluent/test"
require "fluent/plugin/out_pgdist"

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  
end

if File.exist?('/tmp/fluent-plugin-pgdist.debug') then
  $log.level = Logger::DEBUG
else
  $log.level = Logger::ERROR
end
