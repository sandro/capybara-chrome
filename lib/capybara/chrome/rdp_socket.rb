module Capybara::Chrome
  class RDPSocket
    READ_LEN = 4096
    # READ_LEN = 0x3ffffff
    attr_reader :url, :io

    def initialize(url)
      uri = URI.parse(url)
      @url = uri.to_s
      @io = TCPSocket.new(uri.host, uri.port)
    end

    def write(data)
      # io.print data
      io.sendmsg data
    end

    def read
      # io.readpartial(READ_LEN)
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
