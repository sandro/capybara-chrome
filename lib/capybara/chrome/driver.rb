module Capybara::Chrome
  class Driver < Capybara::Driver::Base
    extend Forwardable

    def initialize(app, options={})
      @app = app
      @options = options
      @session = nil
    end

    def_delegators :browser, :visit, :find_css, :html, :evaluate_script, :evaluate_async_script, :execute_script, :status_code, :save_screenshot, :render, :current_url, :header, :console_messages, :error_messages, :dismiss_modal, :accept_modal, :title, :unrecognized_scheme_requests, :wait_for_load

    def browser
      @browser ||= Browser.new(self, port: @options[:port])
    end

    def find_xpath(query)
      nodes = browser.find_xpath(query)
    end

    def start
      browser.start
    end

    def needs_server?
      true
    end

    def wait?
      true
    end

    def reset!
      browser.reset
    end

  end
end
