module Capybara::Chrome
  class RDPSocket
    READ_LEN = 4096
    attr_reader :url, :io

    def initialize(url)
      uri = URI.parse(url)

      @url = url
      @io = TCPSocket.new(uri.host, uri.port)
    end

    def write(data)
      io.print data
    end

    def read
      io.readpartial(READ_LEN)
    end
  end
end
