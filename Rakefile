require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

task :tag do
  puts `git tag #{Capybara::Chrome::VERSION} && git tag | sort -V | tail`
end
