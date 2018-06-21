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

    Capybara.register_driver :chrome do |app|
      driver = Capybara::Chrome::Driver.new(app, port: 9222)
      if driver.browser.chrome_running?
        driver = Capybara::Chrome::Driver.new(app)
      end
      driver.start
      driver
    end

  end
end
