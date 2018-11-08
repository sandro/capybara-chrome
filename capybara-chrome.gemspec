
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "capybara/chrome/version"

Gem::Specification.new do |spec|
  spec.name          = "capybara-chrome"
  spec.version       = Capybara::Chrome::VERSION
  spec.authors       = ["Sandro Turriate"]
  spec.email         = ["sandro.turriate@gmail.com"]

  spec.summary       = %q{Chrome driver for capybara using remote debugging protocol.}
  spec.description   = %q{Chrome driver for capybara using remote debugging protocol.}
  spec.homepage      = "https://github.com/carezone/capybara-chrome"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency("capybara")
  spec.add_runtime_dependency("json")
  spec.add_runtime_dependency("websocket-driver")

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
