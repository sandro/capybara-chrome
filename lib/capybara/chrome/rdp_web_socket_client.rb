module Capybara::Chrome
  class RDPWebSocketClient
    attr_reader :socket, :driver, :messages, :status

    def initialize(url)
      @socket = RDPSocket.new(url)
      @driver = ::WebSocket::Driver.client(socket)

      @messages = []
      @status = :closed

      setup_driver
      start_driver
    end

    def send_msg(msg)
      driver.text msg
    end

    def parse_input
      @driver.parse(@socket.read)
    end

    private

    def setup_driver
      driver.on(:message) do |e|
        messages << e.data
      end

      driver.on(:error) do |e|
        raise WebSocketError.new e.message
      end

      driver.on(:close) do |e|
        raise "closed"
        @status = :closed
      end

      driver.on(:open) do |e|
        @status = :open
      end
    end

    def start_driver
      driver.start
      select [socket.io]
      parse_input until status == :open
    end
  end
end
