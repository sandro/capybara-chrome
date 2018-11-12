require "puma"

module TestServer

  def prefix_doctype(html)
    "<!DOCTYPE html>" + html
  end

  def html_app(html)
    lambda do |env|
      [200, {"Content-Type" => "text/html"}, [html]]
    end
  end

  def run_server(app, host: "127.0.0.1", port: Capybara::Chrome::Service.find_available_port("127.0.0.1"))
    server = Puma::Server.new app
    server.add_tcp_listener host, port
    server.run
    yield({host: host, port: port, server: server})
    server.stop(true)
  end

end
