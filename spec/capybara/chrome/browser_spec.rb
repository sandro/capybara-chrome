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

end
