require "capybara/chrome/version"
require "capybara"
require "websocket/driver"

module Capybara
  module Chrome
    require "capybara/chrome/errors"
    autoload :Configuration, "capybara/chrome/configuration"

    autoload :Driver, "capybara/chrome/driver"
    autoload :Browser, "capybara/chrome/browser"
    autoload :Node, "capybara/chrome/node"
    autoload :Service, "capybara/chrome/service"

    autoload :RDPClient, "capybara/chrome/rdp_client"
    autoload :RDPWebSocketClient, "capybara/chrome/rdp_web_socket_client"
    autoload :RDPSocket, "capybara/chrome/rdp_socket"

    autoload :Debug, "capybara/chrome/debug"

    def self.configure(reset: false)
      @configuration = nil if reset
      yield configuration
    end

    def self.configuration
      @configuration ||= Configuration.new
    end

    def self.wants_to_quit
      @wants_to_quit
    end

    def self.trap_interrupt
      $stderr.puts "TRAPPING"
      previous_interrupt = trap("INT") do
        $stderr.puts "IN INT"
        @wants_to_quit = true
        if previous_interrupt.respond_to?(:call)
          previous_interrupt.call
        else
          exit 1
        end
      end
    end

    Capybara.register_driver :chrome do |app|
      $stderr.puts "REGISTER DRIVER"
      driver = Capybara::Chrome::Driver.new(app, port: configuration.chrome_port)
      if driver.browser.chrome_running?
        driver = Capybara::Chrome::Driver.new(app)
      end
      driver.start
      Capybara::Chrome.trap_interrupt if Capybara::Chrome.configuration.trap_interrupt?
      driver
    end

  end
end
