module Capybara::Chrome
  class RDPSocket
    READ_LEN = 4096
    attr_reader :url, :io

    def initialize(url)
      uri = URI.parse(url)
      @url = uri.to_s
      @io = TCPSocket.new(uri.host, uri.port)
    end

    def write(data)
      io.sendmsg data
    end

    def read
      buf = ""
      loop do
        buf << io.recv_nonblock(READ_LEN)
      end
    rescue IO::EAGAINWaitReadable
      if buf.size == 0
        puts "buf is #{buf.size}"
        puts caller[0..10]
      end
      buf
    end
  end
end
