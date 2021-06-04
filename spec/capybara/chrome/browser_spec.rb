RSpec.describe Capybara::Chrome::Browser do
  include TestServer

  def get_browser
    driver = Capybara::Chrome::Driver.new(nil, port: 9222); driver.start
    driver.browser
  end

  describe "#html" do
    it "returns the page html" do
      html = "<html><head><title>Test Suite</title></head><body><h1>HI</h1></body></html>"
      run_server(html_app(prefix_doctype(html))) do |opts|
        browser = get_browser
        browser.visit "http://#{opts[:host]}:#{opts[:port]}/"
        puts browser.html
        expect(browser.html).to eq(html)
      end
    end
  end

  describe "#chrome_args" do
    let(:remote_opt) { ["--remote-debugging-port=9222"]}
    let(:browser) { Capybara::Chrome::Browser.new(nil, port: 9222) }

    it "returns defaults" do
      expect(browser.chrome_args).to eq(
        Capybara::Chrome::Service::CHROME_ARGS + remote_opt
      )
    end

    it "returns custom" do
      args = ["--headless", "--enable-automation"]
      Capybara::Chrome.configuration.chrome_args = args
      expect(browser.chrome_args).to eq(
        args + remote_opt
      )
    end
  end

end
